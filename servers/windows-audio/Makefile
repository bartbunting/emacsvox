POWERSHELL = powershell.exe
BUILD_SCRIPT = $(shell wslpath -m $(CURDIR)/build.ps1)
PLAYER = ../windows-play

all:
	-$(PLAYER) --stop
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)"
	chmod +x bin/WindowsPlay.exe $(PLAYER)

clean:
	-$(PLAYER) --stop
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Clean

.PHONY: all clean
