FROM ubuntu:xenial

RUN apt-get -qq update && \
    apt-get -qq install -y \
        git \
        python-pip \
        # redis
        redis-server \
        # install mysql client and dev libraries, needed by python install
        libmysqlclient-dev mysql-client \
        # software-properties-common provides the apt-add-repository command
        software-properties-common \
        # Also install vim for convenience in debugging etc
        vim

# install nginx
RUN apt-add-repository -y ppa:nginx/stable && \
    apt-get -qq update && \
    apt-get install -y nginx

# install some system-wide pip packages
RUN pip install --upgrade \
    pip \
    supervisor \
    redis

ENV HOME=/home/airflow
WORKDIR $HOME

COPY config $HOME/config

# Setup logging destinations for supervisor
ENV SUPERVISOR_DIR=/var/log/supervisord \
    SUPERVISOR_CHILD_LOG_DIR=/var/log/supervisord/processes \
    SUPERVISOR_PID_DIR=/var/run/supervisord

RUN mkdir -p \
    $SUPERVISOR_DIR \
    $SUPERVISOR_CHILD_LOG_DIR \
    $SUPERVISOR_PID_DIR

# Finally, configure, download and install airflow
ENV AIRFLOW_CODE_PATH=$HOME/code/incubator-airflow \
    AIRFLOW_HOME=/home/airflow/airflow

RUN mkdir -p $AIRFLOW_HOME && \
    ln -s $HOME/config/airflow.cfg $AIRFLOW_HOME/airflow.cfg

RUN mkdir -p $HOME/code && \
    git clone \
        --branch 1.8.2 \
        https://www.github.com/apache/incubator-airflow \
        $AIRFLOW_CODE_PATH && \
    pip install -e $AIRFLOW_CODE_PATH[celery,gcp_api,mysql]

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


ENTRYPOINT [ "supervisord", "--nodaemon", "-c", "config/supervisord.conf" ]
