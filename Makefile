run: build
	docker run -it --rm ianblenke/freeswitch

build:
	docker build -t ianblenke/freeswitch .
