
ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
  ifeq ($(GNUSTEP_MAKEFILES),)
    $(warning )
    $(warning Unable to obtain GNUSTEP_MAKEFILES setting from gnustep-config!)
    $(warning Perhaps gnustep-make is not properly installed,)
    $(warning so gnustep-config is not in your PATH.)
    $(warning )
    $(warning Your PATH is currently $(PATH))
    $(warning )
  endif
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

-include config.make

PACKAGE_NAME = Performance
PACKAGE_VERSION = 0.3.3
Performance_INTERFACE_VERSION=0.3
SVN_BASE_URL = svn+ssh://svn.gna.org/svn/gnustep/libs
SVN_MODULE_NAME = performance

NEEDS_GUI = NO

TEST_TOOL_NAME=

LIBRARY_NAME=Performance
DOCUMENT_NAME=Performance

Performance_OBJC_FILES += \
	GSCache.m \
	GSFIFO.m \
	GSIOThreadPool.m \
	GSLinkedList.m \
	GSThreadPool.m \
	GSThroughput.m \
	GSTicker.m \
	GSIndexedSkipList.m \
	GSSkipMutableArray.m \


Performance_HEADER_FILES += \
	GSCache.h \
	GSFIFO.h \
	GSIOThreadPool.h \
	GSLinkedList.h \
	GSThreadPool.h \
	GSThroughput.h \
	GSTicker.h \
	GSSkipMutableArray.h \


Performance_AGSDOC_FILES += \
	GSCache.h \
	GSFIFO.h \
	GSIOThreadPool.h \
	GSLinkedList.h \
	GSThreadPool.h \
	GSThroughput.h \
	GSTicker.h \
	GSSkipMutableArray.h


# Optional Java wrappers for the library
JAVA_WRAPPER_NAME = Performance

Performance_HEADER_FILES_INSTALL_DIR = Performance

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/library.make
# If JIGS is installed, automatically generate Java wrappers as well.
# Because of the '-', should not complain if java-wrapper.make can't be
# found ... simply skip generation of java wrappers in that case.
-include $(GNUSTEP_MAKEFILES)/java-wrapper.make
include $(GNUSTEP_MAKEFILES)/test-tool.make
include $(GNUSTEP_MAKEFILES)/documentation.make

-include GNUmakefile.postamble
