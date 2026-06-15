PREFIX ?= /usr
RPMMACRODIR ?= $(PREFIX)/lib/rpm/macros.d
RPMSCRIPTDIR ?= $(PREFIX)/lib/rpm/rust-rpm-macros

.PHONY: install
install:
	install -D -m644 macros.buildsystem.rustcrates $(DESTDIR)$(RPMMACRODIR)/macros.buildsystem.rustcrates
	install -D -m644 macros.buildsystem.rust $(DESTDIR)$(RPMMACRODIR)/macros.buildsystem.rust
	install -D -m644 macros.rust $(DESTDIR)$(RPMMACRODIR)/macros.rust
	install -D -m755 rustcrates-gen-feature-specparts.sh $(DESTDIR)$(RPMSCRIPTDIR)/rustcrates-gen-feature-specparts.sh
