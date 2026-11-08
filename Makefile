# Chicken Gun (порт с нуля) — theos, iOS 6.1 SDK, OpenGL ES 2.0
export ARCHS = armv7
# SDK 6.1, минимальная версия iOS 6.0 (комментарий не в той же строке: пробелы перед # попали бы в значение TARGET)
export TARGET = iphone:clang:6.1:6.0

# export THEOS_DEVICE_IP = 192.168.x.x   # для `make package install`

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ChickenGun

ChickenGun_FILES = $(wildcard src/*.m) $(wildcard src/*.c)
ChickenGun_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore OpenGLES OpenAL AVFoundation
ChickenGun_CFLAGS = -fobjc-arc -Wall -O2 -Isrc

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache"
