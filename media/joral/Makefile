ifeq ($(MEDIA_PARAM), )
    MEDIA_PARAM:=../Makefile.param
    include $(MEDIA_PARAM)
endif

export LC_ALL=C
SHELL:=/bin/bash

CURRENT_DIR := $(shell pwd)
# ab-boot: platform A/B update machinery (misc_ab, health check, swupdate
# config + trust store) — swupdate-implementation-plan.md
SUBDIRS := satisense-edge media-gateway ab-boot

.PHONY: all clean distclean

all:
	@set -e; \
	for d in $(SUBDIRS); do \
		echo "[JORAL] build $$d"; \
		$(MAKE) -C $$d; \
		$(MAKE) -C $$d install; \
		if [ -d "$(CURRENT_DIR)/$$d/out" ]; then \
			mkdir -p "$(RK_MEDIA_OUTPUT)"; \
			cp -raf "$(CURRENT_DIR)/$$d/out"/* "$(RK_MEDIA_OUTPUT)/"; \
		fi; \
	done
	@echo "build joral done"

clean:
	@set -e; \
	for d in $(SUBDIRS); do \
		if [ -d $$d ]; then $(MAKE) -C $$d clean; fi; \
	done

distclean: clean
