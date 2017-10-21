FROM ubuntu:xenial

RUN apt-get -qq update && \
    apt-get -qq install -y \
        git \
        python-pip \
        # redis
        redis-server redis-tools \
        # install python mysql connector and mysql client
        python-mysql.connector mysql-client \
        # software-properties-common provides the apt-add-repository command
        software-properties-common \
        # Also install vim for convenience in debugging etc
        vim

# install mysql-server: TODO, remove this in favor of cloud SQL
# Various fixes needed to get this to work:
#  1. Set default password for debconf prompts (see: https://gist.github.com/sheikhwaqas/9088872)
#  2. Set table directory permissions (see: https://stackoverflow.com/questions/9083408/fatal-error-cant-open-and-lock-privilege-tables-table-mysql-host-doesnt-ex)
#  3. Tell docker to store the contents of /var/lib/mysql as a VOLUME
RUN echo "mysql-server mysql-server/root_password password root" | debconf-set-selections && \
    echo "mysql-server mysql-server/root_password_again password root" | debconf-set-selections && \
    apt-get install -y -q mysql-server && \
    service mysql start && \
    mysql_secure_installation -proot -D && \
    mysql -u root -p root --execute "
        UNINSTALL PLUGIN validate_password;
        CREATE DATABASE airflow;
        CREATE USER 'airflow'@'localhost' IDENTIFIED BY 'airflow';
        GRAINT ALL PRIVILEGES ON '*.*' TO 'airflow'@'localhost'"

VOLUME /var/lib/mysql

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
    SUPERVISOR_CHILD_LOG_DIR=$SUPERVISOR_DIR/child_logs

RUN mkdir -p $SUPERVISOR_DIR $SUPERVISOR_CHILD_LOG_DIR

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
    pip install -e $AIRFLOW_CODE_PATH[celery,gcp_api]

ENTRYPOINT [ "supervisord", "-c", "config/supervisord.conf" ]
