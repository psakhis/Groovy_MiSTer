#ifndef  __PACKET_PARSE_H__
#define __PACKET_PARSE_H__

// this cannot be too big, too big will make unroll fail
#define MAX_IPV6_OPT 8

struct pkthdrs {
	int family;
	struct ethhdr  *eth;
	union {
		struct iphdr   *iph;
		struct ipv6hdr *iph6;
	};
	struct udphdr  *udp;
};

#define access_obj_ok(obj, end) ((void *)(obj + 1) <= end)

#define NEXTHDR_HOP		0	/* Hop-by-hop option header. */
#define NEXTHDR_TCP		6	/* TCP segment. */
#define NEXTHDR_UDP		17	/* UDP message. */
#define NEXTHDR_IPV6		41	/* IPv6 in IPv6 */
#define NEXTHDR_ROUTING		43	/* Routing header. */
#define NEXTHDR_FRAGMENT	44	/* Fragmentation/reassembly header. */
#define NEXTHDR_GRE		47	/* GRE header. */
#define NEXTHDR_ESP		50	/* Encapsulating security payload. */
#define NEXTHDR_AUTH		51	/* Authentication header. */
#define NEXTHDR_ICMP		58	/* ICMP for IPv6. */
#define NEXTHDR_NONE		59	/* No next header */
#define NEXTHDR_DEST		60	/* Destination options header. */
#define NEXTHDR_SCTP		132	/* SCTP message. */
#define NEXTHDR_MOBILITY	135	/* Mobility header. */

#define NEXTHDR_MAX		255

#define ipv6_optlen(p)  (((p)->hdrlen+1) << 3)
#define ipv6_authlen(p) (((p)->hdrlen+2) << 2)

#define check_opt_hdr()						\
	do {							\
								\
	} while(0);						\

static inline struct udphdr *parse_ipv6(struct ipv6hdr *iph6, void *end)
{
	struct ipv6_opt_hdr *oh;
	u8 nexthdr;
	void *pos;
	int ol, i;

	pos = (void *)(iph6 + 1);
	nexthdr = iph6->nexthdr;

#if defined(__clang__)
#pragma unroll
#endif
	for (i = 0; i < MAX_IPV6_OPT; ++i) {
		oh = (struct ipv6_opt_hdr *)pos;

		if (!access_obj_ok(oh, end))
			return NULL;

		switch(nexthdr) {
		case NEXTHDR_SCTP:
		case NEXTHDR_ICMP:
		case NEXTHDR_NONE:
		case NEXTHDR_TCP:
		case NEXTHDR_IPV6:
			return NULL;

		case NEXTHDR_UDP:
			return (void *)(iph6 + 1);

		case NEXTHDR_AUTH:
			ol = ipv6_authlen(oh);
			break;

		case NEXTHDR_FRAGMENT:
			ol = 8;
			break;

		case NEXTHDR_HOP:
		case NEXTHDR_ROUTING:
		case NEXTHDR_GRE:
		case NEXTHDR_ESP:
		case NEXTHDR_DEST:
		case NEXTHDR_MOBILITY:
			ol = ipv6_optlen(oh);
			break;
		default:
			 return NULL;
		}

		nexthdr = oh->nexthdr;
		pos += ol;
	}

	return NULL;
}

static inline int packet_parse(struct pkthdrs *hdrs, void *pkt, void *end)
{
	struct ethhdr  *eth;
	struct iphdr   *iph;
	struct ipv6hdr *iph6;
	struct udphdr  *udp;
	u8 *p;

	eth = pkt;

	if (!access_obj_ok(eth, end))
		return 0;

	p = (u8 *)&eth->h_proto;

	// ipv4
	if (p[0] == 0x08 || p[1] == 0x0) {
		iph = pkt + sizeof(*eth);
		if (!access_obj_ok(iph, end))
			return 0;

		if (iph->protocol != IPPROTO_UDP)
			return 0;

		if (5 == iph->ihl) {
			udp = (void *)iph + 20;
		} else {
			udp = (void*)iph + (iph->ihl << 2);

			if ((void *)(udp + 1) > end)
				return 0;
		}

		if (!access_obj_ok(udp, end))
			return 0;

		hdrs->eth = eth;
		hdrs->iph = iph;
		hdrs->udp = udp;
		hdrs->family = AF_INET;
		return 1;
	}

	// ipv6
	if (p[0] == 0x86 && p[1] == 0xDD) {
		iph6 = pkt + sizeof(*eth);
		if (!access_obj_ok(iph6, end))
			return 0;

		udp = parse_ipv6(iph6, end);
		if (!udp)
			return 0;

		if (!access_obj_ok(udp, end))
			return 0;

		hdrs->eth  = eth;
		hdrs->iph6 = iph6;
		hdrs->udp  = udp;
		hdrs->family = AF_INET6;
		return 1;
	}

	return 0;
}

#endif


