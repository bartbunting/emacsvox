POWERSHELL = powershell.exe
BUILD_SCRIPT = $(shell wslpath -m $(CURDIR)/build.ps1)
RUNTIME_DIR = runtime
RUNTIME_ARCHIVE = $(RUNTIME_DIR)/vs2022.zip
RUNTIME_URL = https://github.com/dectalk/dectalk/releases/download/2023-10-30/vs2022.zip
RUNTIME_SHA256 = 4a778056c109b37f95ade4b3d3e308b9396b22a4b0629f9756ec0e5051b9636d

all: runtime
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)"
	chmod +x bin/DectalkBridge.exe bin/DectalkBridge32.exe

$(RUNTIME_ARCHIVE):
	mkdir -p $(RUNTIME_DIR)
	curl -L --fail --output $@.tmp "$(RUNTIME_URL)"
	echo "$(RUNTIME_SHA256)  $@.tmp" | sha256sum --check -
	mv $@.tmp $@

runtime: $(RUNTIME_ARCHIVE)
	echo "$(RUNTIME_SHA256)  $(RUNTIME_ARCHIVE)" | sha256sum --check -
	unzip -j -o $(RUNTIME_ARCHIVE) IA32/DECtalk.dll IA32/dtalk_us.dic -d $(RUNTIME_DIR)

clean:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Clean

clean-runtime:
	rm -rf $(RUNTIME_DIR)

.PHONY: all runtime clean clean-runtime
