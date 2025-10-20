run:
	python3.13 example.py

watch args:
	@watchexec -w . -e py -e zig -- just {{args}}
