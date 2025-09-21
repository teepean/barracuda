#######################################################
# Configuration for BarraCUDA project
#######################################################

#WBL 25 Aug 2015 Avoid need for LD_LIBRARY_PATH by using libcudart_static.a in place of libcudart.so
#WBL 28 Feb 2015 compile for Tesla K20 etc (sm_35)
# Modified to target sm_86 and use CUDA 12.9

# cu source files
CUFILES	= $(wildcard *.cu)
# c++ source files
CCFILES	= $(wildcard *.cpp)
# c source files
CFILES	= $(wildcard *.c)
# libraries dependency (zlib)
USERLIB = -lz 

#check for 64bit support and if yes build with it
ifeq ($(shell uname -m),x86_64)
COMMONFLAGS += -m64
endif

#check for pthread support and if yes build with it
ifneq ($(shell ldconfig -p | grep pthread),)
COMMONFLAGS += -DHAVE_PTHREAD
USERLIB += -lpthread
endif

#######################################################
# Default configuration (Modified for CUDA 12.9)
#######################################################
#Cuda installation path (modified to use CUDA 12.9)
CUDA_INSTALL_PATH ?= /usr/local/cuda-13.0
NV_ROOT_PATH := $(HOME)/NVIDIA_CUDA_SDK

# Basic Auto variable setup for SDK
SYSTEM        = $(subst ' ',_,$(shell uname | tr A-Z a-z))
PROJECT_PATH ?= .
EXECUTABLE   ?= $(lastword $(subst /, ,$(PWD)))
#EXCUTABLE ?= barracuda
BINDIR       ?= $(SYSTEM)
ROOTOBJDIR   ?= $(SYSTEM)

# Allow overriding for debug/release via command line (e.g., make DEBUG=1)
ifeq ($(DEBUG),1)
ConfigName = debug
endif

ifeq ($(ConfigName),debug)
verbose = 1
dbg = 1
else
verbose = 0
dbg = 0
endif

################################################################################
# Below is from commom.mk
################################################################################

################################################################################
#
# Common build script
#
################################################################################

.SUFFIXES : .cu .cu_dbg.o .c_dbg.o .cpp_dbg.o .cu_rel.o .c_rel.o .cpp_rel.o .cubin .ptx

################################################################################
# Modified to target only sm_86
################################################################################

# Force sm_86 target (RTX 30/40 series, A100, etc.)
SM_VERSIONS := sm_86

CUDA_INSTALL_PATH ?= /usr/local/cuda-13.0

ifdef cuda-install
	CUDA_INSTALL_PATH := $(cuda-install)
endif

# detect OS
OSUPPER = $(shell uname -s 2>/dev/null | tr [:lower:] [:upper:])
OSLOWER = $(shell uname -s 2>/dev/null | tr [:upper:] [:lower:])
# 'linux' is output for Linux system, 'darwin' for OS X
DARWIN = $(strip $(findstring DARWIN, $(OSUPPER)))

# Basic directory setup
# (override directories only if they are not already defined)
SRCDIR     ?= 
ROOTDIR    ?= 
ROOTBINDIR ?= bin
BINDIR     ?= $(ROOTBINDIR)/$(OSLOWER)
ROOTOBJDIR ?= 

# Compilers
NVCC       := $(CUDA_INSTALL_PATH)/bin/nvcc 
CXX        := g++
CC         := gcc
LINK       := g++ -fPIC

# Includes
INCLUDES  += -I$(CUDA_INSTALL_PATH)/include 

# architecture flag for cubin build
CUBIN_ARCH_FLAG :=

# Warning flags
CXXWARN_FLAGS := \
	-W -Wall \
	-Wimplicit \
	-Wswitch \
	-Wformat \
	-Wchar-subscripts \
	-Wparentheses \
	-Wmultichar \
	-Wtrigraphs \
	-Wpointer-arith \
	-Wcast-align \
	-Wreturn-type \
	-Wno-unused-function \
	$(SPACE)

CWARN_FLAGS := $(CXXWARN_FLAGS) \
	-Wstrict-prototypes \
	-Wmissing-prototypes \
	-Wmissing-declarations \
	-Wnested-externs \
	-Wmain \

# Compiler-specific flags
NVCCFLAGS := #--ptxas-options=-v #additional information on kernels
CXXFLAGS  := $(CXXWARN_FLAGS)
CFLAGS    := $(CWARN_FLAGS)

# Common flags
COMMONFLAGS += $(INCLUDES) -DUNIX

# Debug/release configuration
ifeq ($(dbg),1)
	COMMONFLAGS += -g
	NVCCFLAGS   += -D_DEBUG -lineinfo
	# Add compute-sanitizer memcheck flags
	NVCCFLAGS   += -Xcompiler -rdynamic
	CXXFLAGS    += -O0 -g
	CFLAGS      += -O0 -g
	BINSUBDIR   := debug
	LIBSUFFIX   := D
else 
	COMMONFLAGS += 
	BINSUBDIR   := release
	LIBSUFFIX   :=
	NVCCFLAGS   += --compiler-options -fno-strict-aliasing --compiler-options -fno-inline -w
	CXXFLAGS    += -fno-strict-aliasing -O2 -w
	CFLAGS      += -fno-strict-aliasing -O2 -w
endif

# append optional arch/SM version flags (such as -arch sm_11)
NVCCFLAGS += -arch $(SM_VERSIONS)

# architecture flag for cubin build
CUBIN_ARCH_FLAG :=

# detect if 32 bit or 64 bit system
HP_64 =	$(shell uname -m | grep 64)

# Cuda Libs do 32 and 64-bit automatically
	ifeq "$(strip $(HP_64))" ""
		LIB       := -L$(CUDA_INSTALL_PATH)/lib 
	else
		LIB       := -L$(CUDA_INSTALL_PATH)/lib64  
	endif


# Dynamically linking to CUDA and CUDART
#LIB += -lcudart 

# Static linking to CUDA and CUDART
LIB +=  -lcudart_static
LIB +=  -ldl -lrt #also needed when swap to libcudart_static.a


# add userlib at the end
LIB += $(USERLIB)

# Lib/exe configuration
ifneq ($(STATIC_LIB),)
	TARGETDIR := $(LIBDIR)
	TARGET   := $(subst .a,$(LIBSUFFIX).a,$(LIBDIR)/$(STATIC_LIB))
	LINKLINE  = ar rucv $(TARGET) $(OBJS) 
else
	# Device emulation configuration
	ifeq ($(emu), 1)
		NVCCFLAGS   += -deviceemu
		CUDACCFLAGS += 
		BINSUBDIR   := emu$(BINSUBDIR)
		# consistency, makes developing easier
		CXXFLAGS		+= -D__DEVICE_EMULATION__
		CFLAGS			+= -D__DEVICE_EMULATION__
	endif
	TARGETDIR := $(BINDIR)/$(BINSUBDIR)
#	TARGET    := $(TARGETDIR)/$(EXECUTABLE)
	TARGET    := $(TARGETDIR)/barracuda
	LINKLINE  = $(LINK) -o $(TARGET) $(OBJS) $(LIB)
endif

# check if verbose 
ifeq ($(verbose), 1)
	VERBOSE :=
else
	VERBOSE := @
endif

################################################################################
# Check for input flags and set compiler flags appropriately
################################################################################
ifeq ($(fastmath), 1)
	NVCCFLAGS += -use_fast_math
endif

ifeq ($(keep), 1)
	NVCCFLAGS += -keep
	NVCC_KEEP_CLEAN := *.i* *.cubin *.cu.c *.cudafe* *.fatbin.c *.ptx
endif

ifdef maxregisters
	NVCCFLAGS += -maxrregcount $(maxregisters)
endif

# Add cudacc flags
NVCCFLAGS += $(CUDACCFLAGS)

# workaround for mac os x cuda 1.1 compiler issues
ifneq ($(DARWIN),)
	NVCCFLAGS += --host-compilation=C
endif

# Add common flags
NVCCFLAGS := $(COMMONFLAGS) $(NVCCFLAGS)
CXXFLAGS := $(COMMONFLAGS) $(CXXFLAGS)
CFLAGS := $(COMMONFLAGS) $(CFLAGS)

ifeq ($(nvcc_warn_verbose),1)
	NVCCFLAGS += $(addprefix --compiler-options ,$(CXXWARN_FLAGS)) 
	NVCCFLAGS += --compiler-options -fno-strict-aliasing
endif

################################################################################
# Set up object files
################################################################################
OBJDIR := $(ROOTOBJDIR)/$(BINSUBDIR)/objs
OBJS +=  $(patsubst %.cpp,$(OBJDIR)/%.cpp.o,$(notdir $(CCFILES)))
OBJS +=  $(patsubst %.c,$(OBJDIR)/%.c.o,$(notdir $(CFILES)))
OBJS +=  $(patsubst %.cu,$(OBJDIR)/%.cu.o,$(notdir $(CUFILES)))
DEPS = $(patsubst %.o,%.d,$(OBJS))

################################################################################
# Set up cubin output files
################################################################################
CUBINDIR := $(SRCDIR)data
CUBINS +=  $(patsubst %.cu,$(CUBINDIR)/%.cubin,$(notdir $(CUBINFILES)))

################################################################################
# Set up PTX output files
################################################################################
PTXDIR := $(SRCDIR)data
PTXBINS +=  $(patsubst %.cu,$(PTXDIR)/%.ptx,$(notdir $(PTXFILES)))

################################################################################
# Rules
################################################################################

# This rule compiles .c files
$(OBJDIR)/%.c.o : $(SRCDIR)%.c $(C_DEPS)
	$(VERBOSE)$(CC) $(CFLAGS) -M $< | sed 's|^.*.o:|$(OBJDIR)/$<.o:|' > $(OBJDIR)/$<.d
	$(VERBOSE)$(CC) $(CFLAGS) -o $@ -c $<

# This rule compiles .cpp files
$(OBJDIR)/%.cpp.o : $(SRCDIR)%.cpp $(C_DEPS)
	$(VERBOSE)$(CXX) $(CXXFLAGS) -o $@ -c $<

# This is the corrected rule for compiling .cu files
$(OBJDIR)/%.cu.o : $(SRCDIR)%.cu $(CU_DEPS)
	$(VERBOSE)$(NVCC) $(NVCCFLAGS) -arch $(SM_VERSIONS) -M $< | sed 's|^.*.o :|$(OBJDIR)/$<.o :|' > $(OBJDIR)/$<.d
	$(VERBOSE)$(NVCC) $(NVCCFLAGS) -arch $(SM_VERSIONS) -o $@ -c $< 2>&1 | sed 's/(\([0-9]*\)):/:\1:/'

# These rules are for generating .cubin and .ptx files if needed
$(CUBINDIR)/%.cubin : $(SRCDIR)%.cu cubindirectory
	$(VERBOSE)$(NVCC) $(CUBIN_ARCH_FLAG) $(NVCCFLAGS) -o $@ -cubin $<

$(PTXDIR)/%.ptx : $(SRCDIR)%.cu ptxdirectory
	$(VERBOSE)$(NVCC) $(CUBIN_ARCH_FLAG) $(NVCCFLAGS) -o $@ -ptx $<

# This includes the dependency files
-include $(OBJDIR)/*.d

# The main build rule
all:$(TARGET)
$(TARGET): makedirectories $(OBJS) $(CUBINS) $(PTXBINS) Makefile
	$(VERBOSE)$(LINKLINE)
	$(VERBOSE)echo "Done!"

# Rules for creating directories
cubindirectory:
	$(VERBOSE)mkdir -p $(CUBINDIR)

ptxdirectory:
	$(VERBOSE)mkdir -p $(PTXDIR)

makedirectories:
	$(VERBOSE)mkdir -p $(OBJDIR)
	$(VERBOSE)mkdir -p $(TARGETDIR)

# Rules for cleaning up the project
tidy :
	$(VERBOSE)find . | egrep "#" | xargs rm -f
	$(VERBOSE)find . | egrep "\~" | xargs rm -f

clean : tidy
	$(VERBOSE)echo "Cleaning up ...."
	$(VERBOSE)rm -f $(OBJS)
	$(VERBOSE)rm -f $(DEPS)
	$(VERBOSE)rm -f $(CUBINS)
	$(VERBOSE)rm -f $(PTXBINS)
	$(VERBOSE)rm -f $(TARGET)
	$(VERBOSE)rm -f $(NVCC_KEEP_CLEAN)
	$(VERBOSE)rm -rf $(OBJDIR)
clobber : clean
	$(VERBOSE)rm -rf $(ROOTOBJDIR)


#######################################################
# End of configuration
#######################################################