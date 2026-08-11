POWERSHELL = powershell.exe
BUILD_SCRIPT = $(shell wslpath -m $(CURDIR)/build.ps1)

ifdef OMNIVOX_CSC
COMPILER_ARGS = \
	-CompilerPath "$(shell wslpath -m "$(OMNIVOX_CSC)")" \
	-ReferenceDirectory "$(shell wslpath -m "$(OMNIVOX_REFERENCE_DIR)")"
endif

all:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" \
		$(COMPILER_ARGS)
	chmod +x bin/EloquenceBridge.exe bin/EloquenceBridge32.exe \
		bin/OmnivoxEloquenceHelper32.exe

omnivox-helper:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" \
		$(COMPILER_ARGS) -HelperOnly
	chmod +x bin/OmnivoxEloquenceHelper32.exe

clean:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Clean

.PHONY: all omnivox-helper clean
