DOCKER_USERNAME ?= thiexco
APP_NAME        ?= django-app
GIT_HASH        ?= $(shell git log --format="%h" -n 1)

.DEFAULT_GOAL := help

help:
	@echo "Available targets:"
	@echo "  venv     - Create Python virtual environment"
	@echo "  install  - Install pip dependencies"
	@echo "  run      - Run Django development server"
	@echo "  build    - Build Docker image"
	@echo "  push     - Push image to Docker Hub"
	@echo "  up       - Start all services via docker-compose"
	@echo "  down     - Stop all services"
	@echo "  migrate  - Run migrations inside the container"

venv:
	python3.11 -m venv venv
	@echo "Activate with: source venv/bin/activate"

install:
	pip install --upgrade pip
	pip install -r requirements.txt

run:
	python manage.py makemigrations
	python manage.py migrate
	python manage.py runserver 0.0.0.0:8585

build:
	docker build -t $(DOCKER_USERNAME)/$(APP_NAME):latest .

push:
	docker push $(DOCKER_USERNAME)/$(APP_NAME):latest

up:
	docker-compose down
	docker-compose build --no-cache
	docker-compose up

down:
	docker-compose down

migrate:
	docker exec -it django-web python manage.py makemigrations
	docker exec -it django-web python manage.py migrate
