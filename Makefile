.PHONY: lint

lint:
	find . -name "*.md" | xargs mdl
