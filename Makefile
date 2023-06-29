DIST_NAME   ?= $(shell perl -ne '/^\s*name\s*=\s*(\S+)/ && print $$1' dist.ini )
MAIN_MODULE ?= $(shell perl -ne '/^\s*main_module\s*=\s*(\S+)/ && print $$1' dist.ini )

CARTON      ?= $(shell which carton 2>/dev/null )
CPANFILE_SNAPSHOT ?= $(shell \
  carton exec perl -MFile::Spec -e \
	'($$_) = grep { -e } map{ "$$_/../../cpanfile.snapshot" } \
		grep { m(/lib/perl5$$) } @INC; \
		print File::Spec->abs2rel($$_) . "\n" if $$_' 2>/dev/null )

ON_DEVELOP := $(shell $(CARTON) exec -- \
	dzil nop >/dev/null 2>/dev/null && echo $(CARTON) || echo develop )

ifeq ($(MAIN_MODULE),)
MAIN_MODULE := lib/$(subst -,/,$(DIST_NAME)).pm
endif

CARTON_EXEC =
ifneq ($(CARTON),)
CARTON_EXEC = $(CARTON) exec --
ifeq ($(CPANFILE_SNAPSHOT),)
CPANFILE_SNAPSHOT    := cpanfile.snapshot
endif
endif

CARTON_INSTALL_FLAGS ?= --without develop
PERL_CARTON_PERL5LIB ?= $(PERL5LIB)

.PHONY : test clean realclean develop carton

test : $(CPANFILE_SNAPSHOT)
	@nice $(CARTON_EXEC) prove -lfr t

# This target requires that you add 'requires "Devel::Cover";'
# to the cpanfile and then run "carton" to install it.
testcoverage : $(CPANFILE_SNAPSHOT)
	$(CARTON_EXEC) cover --make "$(MAKE)" -test -ignore . -select ^lib

$(MAKEFILE_TARGET): $(MAKEFILE_SHARE)
	install -m 644 $< $@
	@echo Makefile updated>&2

clean:
	$(CARTON_EXEC) dzil clean || true
	rm -rf .build

realclean: clean
	rm -rf local

update: README.md LICENSE.txt
	@echo Everything is up to date

README.md: $(MAIN_MODULE) dist.ini $(ON_DEVELOP)
	$(CARTON_EXEC) dzil run sh -c "pod2markdown $< > ${CURDIR}/$@"

LICENSE.txt: dist.ini $(ON_DEVELOP)
	$(CARTON_EXEC) dzil run sh -c "install -m 644 LICENSE ${CURDIR}/$@"

$(CPANFILE_SNAPSHOT): $(CARTON) cpanfile
	$(CARTON) install $(CARTON_INSTALL_FLAGS)

develop: $(CPANFILE_SNAPSHOT)
	$(CARTON) install # with develop

carton:
	@echo You must install carton: https://metacpan.org/pod/Carton >&2;
	@false;
