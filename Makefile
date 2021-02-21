SOURCE_DIR = ./src
CCFLAGS += -Wall -Werror -Wno-unused-parameter -pedantic -std=c99 -O2

all: clean bin/external_display_watcher

bin/external_display_watcher:
	@mkdir -p $(@D)
	$(CC) -Wall $(CCFLAGS) -o $@ -lobjc -framework IOKit -framework AppKit src/external_display_watcher.m

clean:
	$(RM) bin/external_display_watcher
