tar: .cache/spellbook.tar

.cache/spellbook.tar: 
	echo "tar new spellbook.tar"
	mkdir -p .cache
	tar -cvf .cache/spellbook.tar ./* 

put_s3: .cache/spellbook.tar
	s3cmd put --acl-public .cache/spellbook.tar s3://infra/spellbook/spellbook.tar
	ls .cache/spellbook.tar

new_role:
	ansible-galaxy init roles/new_empry_role

install:
	mkdir -p community/spellbook/ ;curl -L http://<s3_domain>/infra/spellbook/spellbook.tar | tar -C community/spellbook/ -xv;

install_dependency:
	yum install rhel-system-roles -y

pip_compile:
    uv lock --index-url=https://pypi.tuna.tsinghua.edu.cn/simple/

submodule_update:
	./manage.sh submodule_update

run_ansible_daemon:
	docker run --rm -itd --network host --mount type=bind,source=${PWD}/,dst=/spellbook/  --mount type=bind,source=${HOME}/.ssh/,dst=/root/.ssh/	registry.cn-beijing.aliyuncs.com/spellbook/ansible:v2.16.14 bash

run_offline_file_daemon:
	docker run --rm -itd -p 80:80 registry.cn-beijing.aliyuncs.com/spellbook/offline-file:nginx-v1.0.0

.cache:
	mkdir -p .cache
	
clean: .cache/spellbook.tar
	rm .cache/spellbook.tar

.PHONY: tar put_s3 install clean 