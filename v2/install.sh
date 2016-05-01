#!/bin/bash

#initialization
if [[ "$(cat /etc/freeradius/dictionary | grep 'Max-Monthly-Traffic')" != "" ]]; then
	exit 0
fi

#freeradius


#support ipv6
cat >> /etc/freeradius/radiusd.conf <<EOF
listen {
	ipv6addr = ::
	port = 0
	type = auth
}
listen {
	ipv6addr = ::
	port = 0
	type = acct
}
EOF
#def clients
cat >> /etc/freeradius/clients.conf <<EOF
client 0.0.0.0/0 {
	secret = $radpass
}
client ipv6 {
	ipv6addr = ::
	secret = $radpass
}
EOF
sed -i "s/testing123/$radpass/" /etc/freeradius/clients.conf
if [[ $readsqlclients == "yes" ]]; then
	sed -i "/readclients/ s/#//" /etc/freeradius/sql.conf
	sed -i "/clients.conf$/ s/^/#/" /etc/freeradius/radiusd.conf
fi
#add sql module
sed -i '/sql.conf$/ s/#//' /etc/freeradius/radiusd.conf
sed -i -e "/^\tserver/ s/localhost/$mysql_server/" \
	-e "/^\tlogin/ s/radius/$mysql_login/" \
	-e "/^\tpassword/ s/radpass/$mysql_passwd/" \
	-e "/^\tradius_db/ s/radius/$mysql_name/2" /etc/freeradius/sql.conf
sed -i 's/^#[ \t]sql$/\tsql/' /etc/freeradius/sites-available/default
sed -i 's/^#[ \t]sql$/\tsql/' /etc/freeradius/sites-available/inner-tunnel
#default_eap_type
sed -i '0,/md5/{s/md5/mschapv2/}' /etc/freeradius/eap.conf
#Simultaneous-Use
sed -i "/simul_count_query =/,+3 s/#//" /etc/freeradius/sql/mysql/dialup.conf
#Max-Monthly-Traffic
sed -i '/counter.conf/ s/#//' /etc/freeradius/radiusd.conf
cat >> /etc/freeradius/sql/mysql/counter.conf <<EOF
sqlcounter monthlytrafficcounter {
	counter-name = Monthly-Traffic
	check-name = Max-Monthly-Traffic
	reply-name = Monthly-Traffic-Limit
	sqlmod-inst = sql
	key = User-Name
	reset = monthly
	# DIV 1048576(equal 1024 * 1024),means set trafficcounter unit to MB
	query = "SELECT SUM(acctinputoctets + acctoutputoctets) DIV 1048576 FROM radacct WHERE UserName='%{%k}' AND UNIX_TIMESTAMP(AcctStartTime) > '%b'"
}
EOF
sed -i '/^\tpap/a\\tmonthlytrafficcounter' /etc/freeradius/sites-available/default
cat >> /etc/freeradius/dictionary <<EOF
ATTRIBUTE Max-Monthly-Traffic 3003 integer
ATTRIBUTE Monthly-Traffic-Limit 3004 integer
EOF

#sim-use new
sed -i '/Session database, used for checking Simultaneous-Use. Either the radutmp/d' /etc/freeradius/sites-available/default
sed -i '/\<radutmp\>/ s/^#//' /etc/freeradius/sites-available/default
cat >> /etc/freeradius/radiusd.conf <<EOF
session {
    radutmp
    sql
}
radutmp {
        filename = ${logdir}/radutmp
        username = %{User-Name}
        case_sensitive = yes
        check_with_nas = yes
        perm = 0600
        callerid = "yes"
    }
radutmp sradutmp {
        filename = ${logdir}/sradutmp
        perm = 0644
        callerid = "no"
    }
EOF

#timezone
bash -c "echo $time_zone > /etc/timezone"
dpkg-reconfigure -f noninteractive tzdata
