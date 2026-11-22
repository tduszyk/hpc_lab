clone() { # id name ip cores mem
	qm clone 9001 $1 --name $2 --full 1
	qm set $1 --cores $4 --memory $5 --ipconfig1 ip=10.10.0.$3/24
	qm start $1
}

clone 101 head 10 4 6144
clone 102 login 11 2 2048
for i in 1 2 3 4; do clone 11$i c0$i 2$i 2 2048; done
