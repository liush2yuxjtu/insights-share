.PHONY: help test lint stub stop install clean

PLUGIN_ROOT := $(shell pwd)
PORT        ?= 7799
PIDFILE     := $(HOME)/.claude/insights/server.pid

help:
	@echo "insights-share — make targets"
	@echo "  make test       run tests/run.sh (60+ assertions)"
	@echo "  make lint       shellcheck + json + py_compile"
	@echo "  make stub       start the self-host stub server on port $(PORT)"
	@echo "  make stop       stop the stub server"
	@echo "  make install    register marketplace + install hint"
	@echo "  make clean      remove cache and stub state"

test:
	@CLAUDE_PLUGIN_ROOT=$(PLUGIN_ROOT) bash tests/run.sh

lint:
	@shellcheck -s bash scripts/*.sh tests/*.sh
	@python3 -m py_compile examples/server-stub.py
	@python3 -c "import json; \
[json.load(open(p)) for p in ['.claude-plugin/plugin.json','hooks/hooks.json','examples/insight.example.json']]"
	@echo "lint OK"

stub:
	@mkdir -p $(HOME)/.claude/insights
	@INSIGHTS_BIND_PORT=$(PORT) nohup python3 examples/server-stub.py \
	    > $(HOME)/.claude/insights/server.log 2>&1 & echo $$! > $(PIDFILE)
	@sleep 1
	@curl -sS --max-time 1 http://127.0.0.1:$(PORT)/healthz | grep -q ok \
	    && echo "stub up on http://127.0.0.1:$(PORT) (pid=$$(cat $(PIDFILE)))" \
	    || (echo "stub failed to start" && tail -20 $(HOME)/.claude/insights/server.log && exit 1)

stop:
	@if [ -f $(PIDFILE) ]; then \
	    kill $$(cat $(PIDFILE)) 2>/dev/null || true; \
	    rm -f $(PIDFILE); \
	    echo "stopped"; \
	else \
	    pkill -f 'examples/server-stub.py' 2>/dev/null && echo "killed orphans" || echo "not running"; \
	fi

install:
	@echo "Run inside Claude Code:"
	@echo "  /plugin marketplace add $(HOME)/.claude/local-marketplaces/insights-share-marketplace"
	@echo "  /plugin install insights-share@insights-share-marketplace"
	@echo "  /reload-plugins"

clean:
	@rm -f $(HOME)/.claude/insights/cache.json \
	       $(HOME)/.claude/insights/server-stub.json \
	       $(HOME)/.claude/insights/last-trigger.log
	@rm -rf $(HOME)/.claude/insights/outbox
	@echo "cleaned"
