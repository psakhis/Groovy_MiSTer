Groovy-Server

Recommended script to start for received buffers

poc.sh
	clear
	sudo sysctl -w net.core.rmem_max=2097152
	poc -verbose 0
