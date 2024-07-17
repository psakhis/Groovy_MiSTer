/* SPDX-License-Identifier: GPL-2.0 */

#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <linux/if_vlan.h>
#include <sys/socket.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <linux/udp.h>
#include <arpa/inet.h>
#include <stdbool.h>
#include <stddef.h>

#include "ip6.h"
#include "packet_parse.h"


#define UDP_PORT 32100
#define UDP_PORT_INPUTS 32101

struct {
	__uint(type, BPF_MAP_TYPE_XSKMAP);
	__type(key, __u32);
	__type(value, __u32);
	__uint(max_entries, 1);
} xsks_map SEC(".maps");

/*struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__type(key, __u32);
	__type(value, __u32);
	__uint(max_entries, 1);
} xdp_stats_map SEC(".maps");*/


static __always_inline
bool check_ipport(struct pkthdrs hdrs)
{		
	if (hdrs.family == AF_INET) 
	{
		return ((ntohs(hdrs.udp->dest) == UDP_PORT) || (ntohs(hdrs.udp->dest) == UDP_PORT_INPUTS));		
	} 
	else 
	{
		return (false);
	}		
}

SEC("xdp_groovymister")
int xdp_sock_prog(struct xdp_md *ctx)
{
    int index = ctx->rx_queue_index;
   // __u32 *pkt_count;
    struct pkthdrs hdrs;
    	
  /*  
    pkt_count = bpf_map_lookup_elem(&xdp_stats_map, &index);
    if (pkt_count)
    {
        // We pass every other packet 
        if ((*pkt_count)++ & 1)
          return XDP_PASS;       
    }*/
    
    
    //UDP?    
    void *pkt, *end;
    pkt = (void *)(long)ctx->data;
    end = (void *)(long)ctx->data_end;
    
    if (!packet_parse(&hdrs, pkt, end))
    {
    	return XDP_PASS;    
    }
    
    //UDP PORT?
    if (!check_ipport(hdrs))
    {
	return XDP_PASS;	
    }	       	  	

    /* A set entry here means that the correspnding queue_id
     * has an active AF_XDP socket bound to it. */     
    if (bpf_map_lookup_elem(&xsks_map, &index))    
    {
        return bpf_redirect_map(&xsks_map, index, 0);
    }       

    return XDP_PASS;
  
}

char _license[] SEC("license") = "GPL";
