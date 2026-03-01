CLI = ./bin/overmind

.PHONY: build start shutdown ps run logs stop kill send session clean test e2e latency

build:
	mix build

start: build
	$(CLI) start

shutdown:
	$(CLI) shutdown

ps:
	$(CLI) ps

run:
	$(CLI) run "$(CMD)"

logs:
	$(CLI) logs $(ID)

stop:
	$(CLI) stop $(ID)

kill:
	$(CLI) kill $(ID)

send:
	$(CLI) send $(ID) "$(MSG)"

session:
	$(CLI) run --type session

clean:
	rm -f ~/.overmind/overmind.sock ~/.overmind/daemon.pid
	-$(CLI) shutdown 2>/dev/null

test:
	mix test

e2e:
	mix e2e

latency:
	time $(CLI) ps
