# app name, the single edit point for the whole Makefile
APP := gen_smtp

DESTDIR ?= install-dir

# current version and release name from the files
VERSION := $(shell cat version)
RELEASE := $(shell cat release)

# for build info
DATETIME := $(shell LC_ALL=C date)
HOSTNAME := $(shell hostname)

# list of erlang sources and beams to make
ERL_SRC := $(wildcard src/*.erl)
BEAMS   := $(patsubst src/%.erl, ebin/%.beam, $(ERL_SRC))

YRL_SRC := $(wildcard src/*.yrl)
YRL_ERL := $(patsubst src/%.yrl, src/%.erl, $(YRL_SRC))
YRL_TGT := $(patsubst src/%.yrl, ebin/%.beam, $(YRL_SRC))

TST_SRC := $(wildcard test/*.erl)
TBEAMS  := $(patsubst test/%.erl, test/%.beam, $(TST_SRC))

.PHONY: html clean eunit dialyze all-tests

####################
# default target
all: compile

ERLC_OPTS = +warn_unused_function \
 +warn_bif_clash +warn_deprecated_function +warn_obsolete_guard +verbose \
 +warn_shadow_vars +warn_export_vars +warn_unused_records \
 +warn_unused_import +warn_export_all +warnings_as_errors \
 -D$(APP)_release=\"$(RELEASE)\" \
 -D$(APP)_version=\"$(VERSION)\" \
 -D$(APP)_built="\"$(DATETIME)\"" \
 -D$(APP)_bhost=\"$(HOSTNAME)\"

ifdef DEBUG
ERLC_OPTS := $(ERLC_OPTS), debug_info
endif

ifdef TEST
ERLC_OPTS := $(ERLC_OPTS), {d, 'TEST'}
endif

compile: ebin/$(APP).app $(YRL_TGT) $(BEAMS)

####################
# yecc comiplation
$(YRL_ERL): $(YRL_SRC)
	erl -eval "yecc:file(\"$<\")." -s erlang halt

$(YRL_TGT): $(YRL_ERL) ebin
	erlc -o ebin -I./include $(ERLC_OPTS) $<

####################
# application compilation
ebin/%.beam: src/%.erl ebin
	erlc -pa ebin -o ebin -I./include $(ERLC_OPTS) $<

ebin/$(APP).app: ebin src/$(APP).app.in
	sed "s/{{VERSION}}/$(VERSION)/" src/$(APP).app.in > ebin/$(APP).app

ebin:
	mkdir -p ebin

####################
# edoc target
doc: html

EDOC_OPTS = {application, $(APP)}, {preprocess, true}
html:
	mkdir -p doc
	sed "s/{{VERSION}}/$(VERSION)/" src/overview.edoc.in > doc/overview.edoc
	erl -noinput -eval 'edoc:application($(APP),".",[$(EDOC_OPTS)]),halt()'

####################
# eunit target
mktest: $(TBEAMS)

$(TBEAMS): $(TST_SRC)
	erlc -pa ebin -o test -I./include $(ERLC_OPTS) $<

eunit: clean compile mktest
	erl -noinput -pa ebin \
		-eval 'ok=eunit:test({application,$(APP)},[verbose])' \
		-s erlang halt
	erl -noinput -pa ebin \
		-eval 'ok=eunit:test({dir, "test"}, [verbose])' \
		-s erlang halt

test: eunit

PLT = .dialyzer_plt
DIALYZER_OPTS = -Wunmatched_returns -Werror_handling
DIALYZER_APPS = erts inets kernel stdlib crypto compiler \
	envx_config envx_logger envx_df envx_lib envx_ssp_resolver \
	envx_commons cowlib cowboy ranch

####################
# dialyzer
dialyze: $(PLT)
	$(MAKE) DEBUG=y clean compile
	dialyzer --plt $< -r . $(DIALYZER_OPTS) --src
	dialyzer --plt $< -r . $(DIALYZER_OPTS)

$(PLT):
	dialyzer --build_plt --output_plt $@ --apps $(DIALYZER_APPS)

all-tests:
	$(MAKE) eunit
	$(MAKE) dialyze

####################
# for manual testing only
shell: ebin/$(APP).app $(BEAMS)
	erl -pa ebin -config monitor.config \
		-eval 'application:ensure_all_started(gen_smtp)'

####################
# cleanup
clean:
	rm -rf doc ebin $(DESTDIR)
	rm -f *.o erl_crash.dump src/TAGS test/*.beam $(YRL_ERL) $(TBEAMS)
