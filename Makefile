QMLTESTRUNNER := $(shell command -v qmltestrunner 2>/dev/null || echo /usr/lib/qt6/bin/qmltestrunner)
QMLLINT := $(shell command -v qmllint 2>/dev/null || echo /usr/lib/qt6/bin/qmllint)
.PHONY: test test-python test-qml lint package install screenshots
test: test-python test-qml
test-python:
	python3 -m unittest discover -s tests -v
test-qml:
	QMLTESTRUNNER=$(QMLTESTRUNNER) ./scripts/test.sh
lint:
	python3 -m compileall -q src tests
	$(QMLLINT) -I contents/ui contents/ui/*.qml contents/config/config.qml
package:
	./scripts/package.sh
install:
	./scripts/install.sh
screenshots:
	QMLTESTRUNNER=$(QMLTESTRUNNER) ./scripts/test.sh scripts/tst_preview.qml
