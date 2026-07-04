# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
# SPDX-License-Identifier: EPL-2.0

REPOS := aion alembic bwosc ctrl-tree edn-cpp kairos kairos-grid maps \
         nomos-maths nomos-rt nomos-studio.el nomos-tauri nomos-topology \
         nous nomos_beam protomatter txlog

.PHONY: lint-reuse lint-reuse-all
lint-reuse:
	reuse lint

lint-reuse-all:
	@for repo in $(REPOS); do \
	  echo "=== $$repo ==="; \
	  (cd ../$$repo && reuse lint) || exit 1; \
	done
	@echo "All repos compliant."
