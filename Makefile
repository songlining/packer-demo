deck: ## Run the presenterm slide deck (-x enables live code execution)
	@command -v presenterm >/dev/null 2>&1 || { echo "presenterm not installed: brew install presenterm"; exit 1; }
	@presenterm -x presenterm/deck.md

.PHONY: deck deck-notes notes

deck-notes: ## present with speaker notes published to a second terminal
	presenterm -x -P presenterm/deck.md

notes: ## run in a second terminal — shows only speaker notes, follows the deck
	presenterm -l presenterm/deck.md
