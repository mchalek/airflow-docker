FROM ubuntu:xenial

RUN apt-get -qq update && \
    apt-get -qq install -y \
        git \
        python-pip \
        supervisor \
        redis-server \
        # install mysql client and dev libraries, needed by python install
        libmysqlclient-dev mysql-client \
        # software-properties-common provides the apt-add-repository command
        software-properties-common \
        # Also install some useful utilities for debugging
        vim curl jq wget less

# install nginx
RUN apt-add-repository -y ppa:nginx/stable && \
    apt-get -qq update && \
    apt-get install -y nginx

# install some system-wide pip packages
RUN pip install --upgrade pip redis

ENV HOME=/home/airflow
WORKDIR $HOME

# Finally, configure, download and install airflow.  Also set C_FORCE_ROOT so that
# celery will not refuse to function
ENV AIRFLOW_CODE_PATH=$HOME/code/incubator-airflow \
    AIRFLOW_HOME=/home/airflow/airflow \
    C_FORCE_ROOT=true

RUN mkdir -p $HOME/code && \
    git clone \
        --branch 1.9.0alpha1 \
        https://www.github.com/apache/incubator-airflow \
        $AIRFLOW_CODE_PATH && \
    pip install -e $AIRFLOW_CODE_PATH[celery,gcp_api,mysql]

# Install configuration
COPY config/airflow.cfg $HOME/config/
COPY code/incubator-airflow/airflow/example_dags/*.py $AIRFLOW_HOME/dags/
RUN mkdir -p $AIRFLOW_HOME/logs && \
    ln -s $HOME/config/airflow.cfg $AIRFLOW_HOME/airflow.cfg

# install mysql-server: TODO, remove this in favor of cloud SQL
# Various fixes needed to get this to work:
#  1. Set default password for debconf prompts (see: https://gist.github.com/sheikhwaqas/9088872)
#  2. Tell docker to store the contents of /var/lib/mysql as a VOLUME
#  3. Remove the validate_password plugin because it dislikes our simple root password; see: https://stackoverflow.com/questions/36301100/how-do-i-turn-off-the-mysql-password-validation
RUN echo "mysql-server mysql-server/root_password password root" | debconf-set-selections && \
    echo "mysql-server mysql-server/root_password_again password root" | debconf-set-selections && \
    apt-get install -y -q mysql-server && \
    service mysql start && \
    mysql_secure_installation -proot -D && \
    mysql --user=root --password=root --execute=" \
        UNINSTALL PLUGIN validate_password; \
        CREATE DATABASE airflow; \
        CREATE USER 'airflow'@'localhost' IDENTIFIED BY 'airflow'; \
        GRANT ALL PRIVILEGES ON *.* TO 'airflow'@'localhost';" && \
    airflow initdb

VOLUME /var/lib/mysql

COPY config/mysqld.cnf /etc/mysql/mysql.conf.d/
# Symbolic link for supervisor config, so that it's clear where this is installed
COPY config/airflow_supervisord.conf $HOME/config
RUN ln -s $HOME/config/airflow_supervisord.conf /etc/supervisor/conf.d/

ENTRYPOINT [ "supervisord", "--nodaemon" ]
