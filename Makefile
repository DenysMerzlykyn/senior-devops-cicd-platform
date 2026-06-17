IMAGE ?= senior-devops-cicd-app:local

.PHONY: install test start docker-build docker-run clean

install:
	cd app && npm install

test:
	cd app && npm test

start:
	cd app && npm start

docker-build:
	docker build -t $(IMAGE) .

docker-run:
	docker run --rm -p 3000:3000 \
		-e ENVIRONMENT=local \
		-e APP_VERSION=local \
		-e APP_SLOT=local \
		$(IMAGE)

clean:
	docker rm -f senior-cicd-blue senior-cicd-green 2>/dev/null || true
