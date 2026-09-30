"""Keep pioarduino's factory post-action current on incremental builds."""
from pathlib import Path

Import("env")

firmware = env.subst("$BUILD_DIR/${PROGNAME}.bin")
factory = env.subst("$BUILD_DIR/${PROGNAME}.factory.bin")
# The platform's factory merger runs only when ElfToBin runs. Track its extra
# images so a partition-only change also rebuilds/repackages the application.
env.Depends(firmware, [env.subst(image[1]) for image in env.get("FLASH_EXTRA_IMAGES", [])])
if not Path(factory).is_file():
    env.AlwaysBuild(firmware)
