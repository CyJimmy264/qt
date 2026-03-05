SPEC := ruby-qt.spec
NAME := ruby-qt
VERSION := $(shell awk '/^Version:/ {print $$2}' $(SPEC))
TOPDIR ?= $(CURDIR)/.rpmbuild
SOURCEDIR := $(TOPDIR)/SOURCES
SRPMDIR := $(TOPDIR)/SRPMS
REPO_ROOT := $(abspath $(CURDIR)/../..)

.PHONY: srpm clean print-version

print-version:
	@echo $(VERSION)

srpm: $(SOURCEDIR)/$(NAME)-$(VERSION).tar.gz
	rpmbuild -bs $(SPEC) \
		--define "_topdir $(TOPDIR)" \
		--define "_sourcedir $(SOURCEDIR)" \
		--define "_srcrpmdir $(SRPMDIR)" \
		--define "dist %{nil}"
	@echo
	@echo "SRPM:"
	@ls -1 $(SRPMDIR)/*.src.rpm

$(SOURCEDIR)/$(NAME)-$(VERSION).tar.gz:
	mkdir -p $(SOURCEDIR)
	git -C $(REPO_ROOT) archive --format=tar.gz --prefix=$(NAME)-$(VERSION)/ -o $@ HEAD

clean:
	rm -rf $(TOPDIR)
