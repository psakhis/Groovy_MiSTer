#!/bin/sh
#
# groovy_netdiag.sh - MiSTer-side ingest counters for a Groovy streaming session.
#
# Answers one question: of the datagrams the host says it sent, how many reached the
# NIC, how many reached the socket, and where the rest went. Read-only; it touches
# nothing but /sys, /proc, /tmp/groovynlc.log and its own snapshots in /tmp.
#
# Usage, from the host over ssh (two calls, so the stream runs in between):
#
#   groovy_netdiag.sh start [iface]
#   ... start the stream, run the content, stop the stream ...
#   groovy_netdiag.sh stop [iface] [frames] [sendPosted] [sendFailed]
#
# frames/sendPosted/sendFailed come from the client's last "[MiSTer][RIO]" line
# before the stream was stopped (setVerbose(1) or higher). Those counters reset in
# CmdInit, so the last line of a session is the session total. Given all three, stop
# reconciles them against what arrived; given none, it just prints the deltas.
#
# The comparison assumes the client sends one command datagram per blit plus one per
# payload packet, and no audio. A client that sends audio, or that uses the frame_dup
# path (matchDeltaBytes == m_RGBSize), will read low against 'expected' for reasons
# that have nothing to do with loss.
#
# Take the baseline before starting the stream. The core truncates its log at each
# CMD_INIT, so log counts are reported as session totals when that happens rather than
# as a delta, while the nic and udp counters are always deltas across the window.
#
# POSIX sh and busybox awk only. No bashisms, no external tools.

SNAP_A=/tmp/gnd.0
SNAP_B=/tmp/gnd.1
GLOG=/tmp/groovynlc.log

MODE=$1
IFACE=${2:-eth0}

usage()
{
	echo "usage: $0 start [iface]"
	echo "       $0 stop [iface] [frames] [sendPosted] [sendFailed]"
	exit 2
}

snapshot()
{
	out=$1
	stats=/sys/class/net/$IFACE/statistics

	if [ ! -d "$stats" ]; then
		echo "no such interface: $IFACE" >&2
		exit 1
	fi

	{
		awk '{ printf "uptime=%s\n", $1 }' /proc/uptime

		# Static context, carried so a run records the link it was taken on. A host
		# NIC faster than what this prints is the rate step the pacing question is about.
		for f in speed mtu; do
			if [ -r "/sys/class/net/$IFACE/$f" ]; then
				v=$(cat "/sys/class/net/$IFACE/$f" 2>/dev/null)
				[ -n "$v" ] && echo "link_$f=$v"
			fi
		done

		for c in rx_packets rx_bytes rx_dropped rx_errors rx_missed_errors \
		         rx_over_errors rx_fifo_errors rx_crc_errors; do
			if [ -r "$stats/$c" ]; then
				echo "nic_$c=$(cat "$stats/$c")"
			fi
		done

		# /proc/net/snmp carries a header row of names then a row of values, per protocol.
		awk '
			/^Udp:/ {
				if (seen == 0) { for (i = 2; i <= NF; i++) k[i] = $i; seen = 1; next }
				for (i = 2; i <= NF; i++) printf "udp_%s=%s\n", k[i], $i
			}
		' /proc/net/snmp

		# Core-side log lines are severity 0, so they are present at any Verbose level.
		if [ -r "$GLOG" ]; then
			echo "log_udp_error=$(grep -c 'UDP_ERROR' "$GLOG" 2>/dev/null || echo 0)"
			echo "log_syncloss=$(grep -c 'SYNCLOSS' "$GLOG" 2>/dev/null || echo 0)"
			echo "log_hkgap=$(grep -c 'HKGAP' "$GLOG" 2>/dev/null || echo 0)"
		else
			echo "log_udp_error=-1"
			echo "log_syncloss=-1"
			echo "log_hkgap=-1"
		fi
	} > "$out"
}

case "$MODE" in
start)
	snapshot "$SNAP_A"
	rm -f "$SNAP_B"
	echo "iface=$IFACE"
	grep -E '^(link_|uptime=)' "$SNAP_A"
	echo "baseline written to $SNAP_A; run the stream, then: $0 stop $IFACE [frames] [sendPosted] [sendFailed]"
	;;

stop)
	if [ ! -r "$SNAP_A" ]; then
		echo "no baseline at $SNAP_A; run '$0 start $IFACE' first" >&2
		exit 1
	fi
	snapshot "$SNAP_B"

	FRAMES=$3
	POSTED=$4
	FAILED=$5

	awk -F= -v frames="$FRAMES" -v posted="$POSTED" -v failed="$FAILED" -v iface="$IFACE" '
		FNR == NR { a[$1] = $2; next }
		{ b[$1] = $2 }
		END {
			window = b["uptime"] - a["uptime"]
			printf "iface=%s link_speed=%s mtu=%s window=%.1fs\n\n",
			       iface, b["link_speed"], b["link_mtu"], window

			printf "%-24s %14s %14s %14s\n", "counter", "start", "end", "delta"
			n = split("nic_rx_packets nic_rx_bytes nic_rx_dropped nic_rx_errors " \
			          "nic_rx_missed_errors nic_rx_over_errors nic_rx_fifo_errors " \
			          "nic_rx_crc_errors udp_InDatagrams udp_NoPorts udp_InErrors " \
			          "udp_RcvbufErrors", keys, " ")
			for (i = 1; i <= n; i++) {
				k = keys[i]
				if (!(k in b)) continue
				d = b[k] - a[k]
				printf "%-24s %14s %14s %14s\n", k, a[k], b[k], d
			}

			rxb = b["nic_rx_bytes"] - a["nic_rx_bytes"]
			if (window > 0)
				printf "\nreceive rate: %.2f MB/s over %.1fs\n", rxb / window / 1048576.0, window

			if (frames != "" && posted != "" && failed != "") {
				expected = (posted - failed) + frames
				rxp = b["nic_rx_packets"] - a["nic_rx_packets"]
				ind = b["udp_InDatagrams"] - a["udp_InDatagrams"]
				rbe = b["udp_RcvbufErrors"] - a["udp_RcvbufErrors"]
				crc = b["nic_rx_crc_errors"] - a["nic_rx_crc_errors"]

				printf "\nhost said: frames=%s sendPosted=%s sendFailed=%s\n", frames, posted, failed
				printf "expected datagrams (posted - failed + frames) = %d\n", expected
				printf "  nic rx_packets    %10d   (%+d vs expected)\n", rxp, rxp - expected
				printf "  udp InDatagrams   %10d   (%+d vs expected)\n", ind, ind - expected
				printf "  udp RcvbufErrors  %10d\n", rbe
				printf "  nic rx_crc_errors %10d\n", crc

				# rx_packets counts every frame on the wire (arp, broadcast, port 32101),
				# so it can only read high. InDatagrams is the count to trust.
				short_nic = (rxp < expected - 8)
				short_udp = (ind < expected - 8)
				printf "\nreading: "
				if (short_nic && short_udp)
					print "lost BEFORE the MiSTer nic. Switch, cable or duplex. Check link_speed at both ends."
				else if (!short_nic && short_udp && rbe > 0)
					print "arrived but not drained. MiSTer ingest; check [HKGAP] and reduce bytes."
				else if (!short_nic && short_udp)
					print "socket saw fewer than the wire, with RcvbufErrors flat. Check udp_NoPorts and other traffic on this box."
				else if (crc > 0)
					print "counts reconcile but crc errors are present. Physical layer: cable or duplex."
				else
					print "nothing lost on the wire. The fault is core-side (SYNCLOSS) or host-side (field handling)."
			}

			# The core truncates /tmp/groovynlc.log at each CMD_INIT unless append mode is
			# on, so a stream started inside the window resets these to zero. When the end
			# count is below the start count the file was truncated, and the end count is
			# already the whole session; otherwise report the delta.
			print "\ncore log lines (/tmp/groovynlc.log):"
			n = split("log_udp_error log_syncloss log_hkgap", lk, " ")
			for (i = 1; i <= n; i++) {
				k = lk[i]
				if (b[k] == -1) { printf "  %-16s (log not readable)\n", k; continue }
				if (b[k] < a[k])
					printf "  %-16s %8s   (log was truncated: this is the whole session)\n", k, b[k]
				else
					printf "  %-16s %8s   (+%d during the window)\n", k, b[k], b[k] - a[k]
			}
		}
	' "$SNAP_A" "$SNAP_B"

	if [ -r "$GLOG" ]; then
		echo ""
		echo "last line of each:"
		for pat in UDP_ERROR SYNCLOSS HKGAP; do
			line=$(grep "$pat" "$GLOG" 2>/dev/null | tail -n 1)
			[ -n "$line" ] && echo "  $line"
		done
	fi
	;;

*)
	usage
	;;
esac
