# ------- Config -------
SHELL := /bin/bash
.DEFAULT_GOAL := help

DC        ?= docker compose
APP_SVC   ?= app
MYSQL_SVC ?= mysql
REDIS_SVC ?= redis
MINIO_SVC ?= minio

PROJECT   ?= shintage-api-server

GO_IN      = $(DC) exec $(APP_SVC) go
SH_IN      = $(DC) exec $(APP_SVC) /bin/sh -lc

# ------- Help -------
.PHONY: help
help: ## コマンド一覧を表示
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mCommands\033[0m\n"} /^[a-zA-Z0-9_\/-]+:.*##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ------- Docker lifecycle -------
.PHONY: build
build:
	$(DC) build

.PHONY: install
install:
	cp .env.example .env
	make build
	make up

.PHONY: up
up: ## コンテナ起動
	$(DC) up

.PHONY: up-d
up-d: ## コンテナ起動（バックグラウンド）
	$(DC) up -d

.PHONY: down
down: ## コンテナ停止・削除（孤児も削除）
	$(DC) down --remove-orphans

.PHONY: restart
restart: ## コンテナ再起動
	$(DC) restart

.PHONY: logs
logs: ## 全サービスのログ追尾
	$(DC) logs -f

.PHONY: ps
ps: ## 稼働中のサービス一覧
	$(DC) ps

.PHONY: shell
shell: ## app コンテナにシェルで入る
	$(DC) exec $(APP_SVC) /bin/bash || $(DC) exec $(APP_SVC) /bin/sh

.PHONY: db-shell
db-shell: ## MySQL コンテナで mysql クライアントを開く（root）
	$(DC) exec $(MYSQL_SVC) sh -lc 'mysql -uroot -p$$MYSQL_ROOT_PASSWORD'

.PHONY: wait-db
wait-db: ## MySQL の起動待ち
	$(DC) exec $(MYSQL_SVC) sh -lc 'until mysqladmin ping -h 127.0.0.1 --silent; do sleep 1; done; echo "MySQL is up"'

# ------- Dev / Run -------
.PHONY: dev
dev: ## Air でホットリロード起動（app 内で .air.toml 使用）
	$(DC) exec -it $(APP_SVC) air -c .air.toml

.PHONY: run
run: ## 一度だけビルド & 実行（app 内）
	$(GO_IN) build -o ./tmp/main .
	$(DC) exec -it $(APP_SVC) ./tmp/main

# ------- Go modules / build -------
.PHONY: tidy
tidy: ## go mod tidy（app 内）
	$(GO_IN) mod tidy

.PHONY: download
download: ## go mod download（app 内）
	$(GO_IN) mod download

.PHONY: go-build
go-build: ## バイナリビルド（app 内, ./tmp/main）
	$(GO_IN) build -o ./tmp/main .

# ------- Lint / Test / Coverage / Vet -------
.PHONY: lint
lint: ## golangci-lint 実行（公式 Docker イメージ）
	docker run --rm -v $$PWD:/app -w /app $(GOLANGCI_IMG) golangci-lint run

.PHONY: fmt
fmt: ## go fmt（app 内）
	$(GO_IN) fmt ./...

.PHONY: vet
vet: ## go vet（app 内）
	$(GO_IN) vet ./...

.PHONY: vuln
vuln: ## 依存の脆弱性チェック（govulncheck を都度取得）
	$(SH_IN) 'GOBIN=$$PWD/tmp/bin go install golang.org/x/vuln/cmd/govulncheck@latest && ./tmp/bin/govulncheck ./...'

.PHONY: test
test: ## 単体テスト（app 内）
	$(GO_IN) test ./...

.PHONY: cover
cover: ## カバレッジ（app 内, HTML 出力）
	$(GO_IN) test ./... -coverprofile=coverage.out
	$(GO_IN) tool cover -func=coverage.out
	$(GO_IN) tool cover -html=coverage.out -o coverage.html
	@echo "open coverage.html"

# ------- Clean / Utility -------
.PHONY: clean
clean: ## 生成物削除（tmp, coverage）
	rm -rf tmp/main tmp/bin coverage.out coverage.html

.PHONY: doctor
doctor: ## 開発環境のヘルスチェック（DB/Redis/Minio の疎通）
	$(DC) exec $(MYSQL_SVC) sh -lc 'mysqladmin ping -h 127.0.0.1 --silent && echo "MySQL OK"' || true
	$(DC) exec $(REDIS_SVC)  sh -lc 'redis-cli ping' || true
	$(DC) exec $(MINIO_SVC)  sh -lc 'wget -qO- http://localhost:9002/ >/dev/null && echo "Minio Console OK" || true' || true
