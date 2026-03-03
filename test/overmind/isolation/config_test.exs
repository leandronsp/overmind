defmodule Overmind.Isolation.ConfigTest do
  use ExUnit.Case

  alias Overmind.Isolation.Config

  @project_dir System.tmp_dir!()

  setup do
    test_dir = Path.join(@project_dir, "overmind_config_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, dir: test_dir}
  end

  describe "parse/1 — no file" do
    test "returns default config when .overmind.yml is absent", %{dir: dir} do
      assert {:ok, config} = Config.parse(dir)
      assert config.services == []
      assert config.isolation.strategy == :ports
      assert config.isolation.port_range == {3100, 3999}
    end
  end

  describe "parse/1 — full config" do
    test "parses services with docker images and ports", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      services:
        db:
          docker: postgres:16
          port: 5432
        cache:
          docker: redis:7
          port: 6379
      isolation:
        strategy: ports
        port_range: 3100-3999
      """)

      assert {:ok, config} = Config.parse(dir)
      assert length(config.services) == 2

      db = Enum.find(config.services, &(&1.name == "db"))
      assert db.image == "postgres:16"
      assert db.port == 5432

      cache = Enum.find(config.services, &(&1.name == "cache"))
      assert cache.image == "redis:7"
      assert cache.port == 6379
    end

    test "parses services with shell commands", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      services:
        web:
          command: bundle exec rails s -p $PORT
          port: 3000
      isolation:
        strategy: ports
        port_range: 4000-4999
      """)

      assert {:ok, config} = Config.parse(dir)
      assert length(config.services) == 1

      web = hd(config.services)
      assert web.name == "web"
      assert web.command == "bundle exec rails s -p $PORT"
      assert web.port == 3000
    end

    test "parses custom port range", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      services:
        db:
          docker: postgres:16
          port: 5432
      isolation:
        strategy: ports
        port_range: 4000-4999
      """)

      assert {:ok, config} = Config.parse(dir)
      assert config.isolation.port_range == {4000, 4999}
    end

    test "parses strategy", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      isolation:
        strategy: ports
        port_range: 3100-3999
      """)

      assert {:ok, config} = Config.parse(dir)
      assert config.isolation.strategy == :ports
    end
  end

  describe "parse/1 — partial configs" do
    test "returns default isolation when only services are declared", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      services:
        db:
          docker: postgres:16
          port: 5432
      """)

      assert {:ok, config} = Config.parse(dir)
      assert config.isolation.port_range == {3100, 3999}
    end

    test "skips services without a port field", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      services:
        noport:
          docker: someimage:1.0
        withport:
          docker: postgres:16
          port: 5432
      """)

      assert {:ok, config} = Config.parse(dir)
      assert length(config.services) == 1
      assert hd(config.services).name == "withport"
    end

    test "handles empty file", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), "")

      assert {:ok, config} = Config.parse(dir)
      assert config.services == []
    end
  end
end
