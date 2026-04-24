.PHONY: run-mvp test-mvp run down run-without-dlsps run-model-setup setup wave5-smoke wave5-soak

run-mvp:
	python run_mvp_backend.py --config configs/mvp-backend.yaml --host 0.0.0.0 --port 5001

test-mvp:
	venv/bin/python -m pytest -q tests/backend_mvp

setup:
	@echo "Downloading models + video (first-time setup)..."
	docker compose -f docker-compose.yaml --profile setup up --build nicu-model-downloader
	@echo ""
	@echo "Setup complete. Run 'make run' to start all services."

run:
	@echo "Clearing stale metrics data..."
	rm -rf metrics/*.csv metrics/*.log metrics/*.json 2>/dev/null || true
	docker compose -f docker-compose.yaml --profile dlsps up --build --remove-orphans -d
	@echo ""
	@echo "All services starting. Open http://localhost:3001 once ready."
	@echo "Run 'make down' to stop."

run-without-dlsps:
	@echo "Clearing stale metrics data..."
	rm -rf metrics/*.csv metrics/*.log metrics/*.json 2>/dev/null || true
	docker compose -f docker-compose.yaml up --build --remove-orphans -d nicu-metrics-collector nicu-backend nicu-ui

run-model-setup:
	docker compose -f docker-compose.yaml --profile setup up --build --remove-orphans nicu-model-downloader

wave5-smoke:
	./scripts/wave5_smoke.sh

wave5-soak:
	./scripts/wave5_soak.sh

down:
	docker compose -f docker-compose.yaml --profile dlsps down
