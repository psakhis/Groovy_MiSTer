export PATH=$PATH:/opt/arm/bin
rm support/groovy/groovy.cpp.o
make _AF_XDP=0
rm support/groovy/groovy.cpp.o
make _AF_XDP=1
