deck: ## Run the presenterm slide deck (-x enables live code execution)
	@command -v presenterm >/dev/null 2>&1 || { echo "presenterm not installed: brew install presenterm"; exit 1; }
	@presenterm -x presenterm/deck.md

.PHONY: deck
