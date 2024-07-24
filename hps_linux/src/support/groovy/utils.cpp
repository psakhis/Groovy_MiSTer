#include <time.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <netinet/ip.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <cstring>
#include <sched.h>

#include "utils.h"

#define PROC_DIR "/proc"
#define STATUS_FILE "status"

double diff_in_ms(struct timespec *start, struct timespec *end)
{
    long seconds_diff = end->tv_sec - start->tv_sec;
    long nanoseconds_diff = end->tv_nsec - start->tv_nsec;
    return (double)(seconds_diff * 1000000 + nanoseconds_diff / 1000) / (double) 1000.0f;
}

void update_iph_checksum(struct iphdr *iph) 
{
    uint16_t *next_iph_u16 = (uint16_t *)iph;
    uint32_t csum = 0;
    iph->check = 0;
    for (uint32_t i = 0; i < sizeof(*iph) >> 1; i++) {
        csum += *next_iph_u16++;
    }
    iph->check = ~((csum & 0xffff) + (csum >> 16));
}

//from menu.cpp
char* getNet(int spec)
{
	int netType = 0;
	struct ifaddrs *ifaddr, *ifa, *ifae = 0, *ifaw = 0;
	static char host[NI_MAXHOST];

	if (getifaddrs(&ifaddr) == -1)
	{
		printf("getifaddrs: error\n");
		return NULL;
	}

	for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next)
	{
		if (ifa->ifa_addr == NULL) continue;
		if (!memcmp(ifa->ifa_addr->sa_data, "\x00\x00\xa9\xfe", 4)) continue; // 169.254.x.x

		if ((strcmp(ifa->ifa_name, "eth0") == 0)     && (ifa->ifa_addr->sa_family == AF_INET)) ifae = ifa;
		if ((strncmp(ifa->ifa_name, "wlan", 4) == 0) && (ifa->ifa_addr->sa_family == AF_INET)) ifaw = ifa;
	}

	ifa = 0;
	netType = 0;
	if (ifae && (!spec || spec == 1))
	{
		ifa = ifae;
		netType = 1;
	}

	if (ifaw && (!spec || spec == 2))
	{
		ifa = ifaw;
		netType = 2;
	}

	if (spec && ifa)
	{
		strcpy(host, "IP: ");
		getnameinfo(ifa->ifa_addr, sizeof(struct sockaddr_in), host + strlen(host), NI_MAXHOST - strlen(host), NULL, 0, NI_NUMERICHOST);
	}

	freeifaddrs(ifaddr);
	return spec ? (ifa ? host : 0) : (char*)netType;
}

void setARMClock(uint8_t clock)
{
	FILE *fp_cpu;
	fp_cpu = fopen("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq", "w");
    	if (!fp_cpu)
    	{
        	return;        	
    	}
    	fprintf(fp_cpu, "%s\n", (clock == 2) ? "1200000" : (clock == 1) ? "1000000" : "800000");
    	fclose(fp_cpu);    	
}

long get_pid_ksoftirqd(int cpu) {
    struct dirent *entry;
    DIR *dp = opendir(PROC_DIR);
    long pid_soft = 0;
    
    if (dp == NULL) {             
        return pid_soft;
    }

    while ((entry = readdir(dp))) {
        if (entry->d_type == DT_DIR) {
            char *endptr;
            long pid = strtol(entry->d_name, &endptr, 10);

            if (*endptr == '\0') { // It's a valid PID directory
                char filepath[256];
                snprintf(filepath, sizeof(filepath), "%s/%ld/%s", PROC_DIR, pid, STATUS_FILE);

                FILE *fp_pid = fopen(filepath, "r");
                if (fp_pid) {
                    char line[256];
                    while (fgets(line, sizeof(line), fp_pid)) {
                        if (strncmp(line, "Name:", 5) == 0) {
                            char name[256];
                            sscanf(line, "Name:\t%s", name);
                            if (strncmp(name, "ksoftirqd/0", 11) == 0 && cpu == 0) // softirqs for CPU_SET 0 (normal is PID=11)
                            {
                            	pid_soft = pid;
                            }
                            if (strncmp(name, "ksoftirqd/1", 11) == 0 && cpu == 1) // softirqs for CPU_SET 1 (normal is PID=17)
                            {
                            	pid_soft = pid;
                            }
                            break;
                        }
                    }
                    fclose(fp_pid);
                }                
            }           
        }
        if (pid_soft) 
        {
        	break;
        }	
    }

    closedir(dp);
    return pid_soft;
}

int find_eth_irq(const char *interface) {
    
    FILE *fp_irq = fopen("/proc/interrupts", "r"); 
    int irq = 0;
    if (fp_irq == NULL) {        
        return irq;
    }    
    
    char line[256];
    char irq_number[8];
    char device_name[256];
    
    while (fgets(line, sizeof(line), fp_irq)) {
        if (strstr(line, interface) != NULL) {
            sscanf(line, "%s %*s %*s %*s %*s %*s %s", irq_number, device_name);
            if (strstr(device_name, interface) != NULL) 
            {    
            	if (sscanf(irq_number, "%d", &irq) != 1)
            	{
            		irq = 0;
            	}                	              
                break;
            }
        }
    }

    fclose(fp_irq);
    return irq;
}

void setRXAffinity(int cpu)
{        
	int irq = find_eth_irq("eth0"); //39	
	
	if (!irq)
	{
		printf("[setRXAffinity][irq][error]\n");
		return;
	}
	
	FILE *fp_irq;
	cpu_set_t set;
	unsigned long mask_bits = 0;

	//Set rx irq affinity
	char numIRQ[2];
	char strAffinity1[25] = "/proc/irq//smp_affinity"; 	
	char strAffinity2[25];
	sprintf(numIRQ, "%d", irq);
	strncpy(strAffinity2, strAffinity1, 10);
	strAffinity2[10] = '\0';
	strcat(strAffinity2, numIRQ);
	strcat(strAffinity2, strAffinity1 + 10);
		
	fp_irq = fopen(strAffinity2, "w");
    	if (!fp_irq)
    	{
        	printf("[setRXAffinity][fopen(fp_irq)][error]\n");
        	return;
    	}
	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	// Convert the CPU mask to a hexadecimal string
    	for (int i = 0; i < CPU_SETSIZE; i++)
    	{
        	if (CPU_ISSET(i, &set))
        	{
            		mask_bits |= (1UL << i);
            	}
        }
    	fprintf(fp_irq, "%lx\n", mask_bits);
    	if (fclose(fp_irq) == EOF)
    	{        	
    		printf("[setRXAffinity][fclose(fp_irq)][error]\n"); 
        	return;
   	}
	
	int pid = get_pid_ksoftirqd(cpu);
	
	if (pid == 0)
	{
		printf("[setRXAffinity][get_pid_ksoftirqd][error]\n");    
		return;
	}
	
	//MAX Priority for softirqs
	
	struct sched_param param;
    	param.sched_priority = 99;
    	if (sched_setscheduler(pid, SCHED_FIFO, &param) == -1)
    	{
    		printf("[setRXAffinity][sched_setscheduler][error]\n");        	
        	return;
    	}
    		
}