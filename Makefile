.PHONY: lint

lint:
	find . -name "*.md" | xargs mdl -r ~MD013,~MD036
