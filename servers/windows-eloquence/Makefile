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
	chmod +x bin/EloquenceBridge.exe bin/EloquenceBridge32.exe

clean:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Clean

.PHONY: all clean
