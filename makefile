BUILD_FLAGS		= -O0 -g -std=c++14 -Wall -Wno-deprecated -Wno-writable-strings
BUILD_PATH		= ./
BINS			= $(BUILD_PATH)/wmctrl
DEV_BIN_PATH	= ./
DEV_BUILD_PATH	= ./bin
DEV_BINS		= $(DEV_BUILD_PATH)/wmctrl
SRC				= ./main.mm
LINK			= -framework Carbon -framework Cocoa -framework ApplicationServices
DIR := ${CURDIR}
NOW := $(shell date "+%s")

all: $(BINS)

install: BUILD_FLAGS=-O2 -std=c++14 -Wall -Wno-deprecated -Wno-writable-strings
install: clean $(BINS)
dev: clean $(DEV_BINS)

.PHONY: all clean install dev

$(DEV_BUILD_PATH):
	mkdir -p $(DEV_BUILD_PATH)

$(BUILD_PATH):
	mkdir -p $(BUILD_PATH)

clean:
	rm -f $(BUILD_PATH)/wmctrl
	rm -rf $(DEV_BUILD_PATH)/wmctrl*
	rm -f $(DEV_BIN_PATH)/wmctrl

$(DEV_BUILD_PATH)/wmctrl: $(SRC) | $(DEV_BUILD_PATH)
	clang++ $^ $(BUILD_FLAGS) -o $@_$(NOW) $(LINK)
	ln -sf $(DIR)/$@_$(NOW) $(DEV_BIN_PATH)/wmctrl

$(BUILD_PATH)/wmctrl: $(SRC) | $(BUILD_PATH)
	clang++ $^ $(BUILD_FLAGS) -o $@ $(LINK)
