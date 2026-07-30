POWERSHELL = powershell.exe
BUILD_SCRIPT = $(shell wslpath -m $(CURDIR)/build.ps1)

all:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)"
	chmod +x bin/EloquenceBridge.exe bin/EloquenceBridge32.exe

clean:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Clean

.PHONY: all clean
