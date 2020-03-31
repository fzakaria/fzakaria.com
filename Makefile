serve: build
	docker run -p 4000:4000 -p 35729:35729 -v $(shell pwd):/src --rm jekyll serve -H 0.0.0.0 --watch --drafts --incremental --livereload

build: Dockerfile Gemfile Gemfile.lock
	docker build -f Dockerfile -t jekyll .

.PHONY: serve build