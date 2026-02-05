#!/bin/bash
set -e

IMAGE_NAME="nginx:1.1.1"
ARTIFACTS_DIR="artifacts"
REPORTS_DIR="reports"
COUNTER_FILE="counter.txt"
LAST_COVERAGE_FILE="last_covarage.txt"
DOCKERFILE="Dockerfile"
NGINX_VERSION="1.28.1"
DATESTAMP=$(date +%Y%m%d_%H%M%S)
REVISION="$NGINX_VERSION-$DATESTAMP"
ARTIFACT_NAME="nginx-$1-$REVISION"
SRC_DIR="src_project/nginx"
CCACHE_DIR="ng_ccache"
VOLUMES="-v $(pwd)/$ARTIFACTS_DIR:/artifacts -v $(pwd)/$REPORTS_DIR:/reports -v $(pwd)/$CCACHE_DIR:/ccache" # Монтируемые дириктории в контейнер

# Обработка исключений

if [ "$1" == "release" ]; then
	echo "	Сборка в режиме $1"
elif [ "$1" == "debug" ]; then
	echo "	Сборка в режиме $1"
elif [ "$1" == "coverage" ]; then
	echo "	Сборка в режиме $1"
else
	echo "	Требуется ровно один аргумент"
	echo "    Используйте: $0 {release|debug|coverage}"
	exit 1
fi

# Проверка на наличие образа в локальном репозитории

if sudo docker images -q "$IMAGE_NAME" | grep -q .; then
	echo "	Образ $IMAGE_NAME найден в локальном репозитории"
else
	echo "	Образ не найден, будет собран новый"
	sudo docker build -t "$IMAGE_NAME" .
fi 

# Запуск контейнера

sudo docker run --rm $VOLUMES "$IMAGE_NAME" \
	bash -c "set -e
		if [ "$1" == "coverage" ]; then # Для coverage скачиваем lcov
			apt install -y lcov
		fi
		case "$1" in
			release)
				./configure --with-cc-opt='-O2 -DNDEBUG' --with-ld-opt='-s'
				make
				make install
				strip /usr/local/nginx/sbin/nginx 	# Удаление отладочной информации
				;;
			debug) ./configure --with-cc-opt='-g -O0'
                                make
                                make install
				;;
			coverage)
				./configure --with-cc-opt='--coverage -g -O0' --with-ld-opt='--coverage' 
				make
    				make install
				/usr/local/nginx/sbin/nginx 	# Запускаем nginx, чтобы собрать данные для lcov

# Сбор данных покрытия
   				mkdir -p /tmp/coverage
				lcov --capture \
					--directory . \
					--output-file /tmp/coverage/total.info \
					--no-checksum \
					--rc lcov_branch_coverage=1
# Фильтрация системных файлов
  				lcov --extract /tmp/coverage/total.info \
					'*/src/*' \
					--output-file /tmp/coverage/filtered.info \
					--rc lcov_branch_coverage=1
# Генерация HTML-отчёта
				genhtml /tmp/coverage/filtered.info \
					--output-directory /reports/coverage/coverage_report_$DATESTAMP \
					--title 'NGINX Coverage' \
					--legend \
					--branch-coverage
# Преобразование сырых данных в человекочитаемый вид				
				lcov --summary /tmp/coverage/filtered.info > /reports/coverage/coverage_summary_$DATESTAMP.txt

				;;
		esac
	
# Упаковка в deb
    				mkdir -p /tmp/pkg/DEBIAN /tmp/pkg/usr/local/nginx
    				cat > /tmp/pkg/DEBIAN/control <<'EOF'
Package: nginx-custom
Version: $NGINX_VERSION
Architecture: amd64
Maintainer: aensidh0@hmail.com
Description: Custom nginx build ($1)
EOF
#Вывод статистики ccache ПОСЛЕ сборки
    				if [ "$1" != "release" ]; then 			# Убираем информацию о сборке из релиза
        				echo '	Статистика ccache ПОСЛЕ сборки:'
        				ccache -s || true
    				fi
				cp -r /usr/local/nginx/sbin/nginx /tmp/pkg/usr/local/nginx/
				dpkg-deb --build /tmp/pkg /artifacts/${ARTIFACT_NAME}_amd64.deb
		"


# Обработка coverage
if [ "$1" = "coverage" ]; then
	COVERAGE=$(grep lines reports/coverage/coverage_summary_$DATESTAMP.txt | awk '{print  $2}' | tr -d '%')
	COVERAGE_FILE="reports/coverage/coverage_value.txt"
        LAST_COV=$(cat "$COVERAGE_FILE")
	echo "	Информация о покрытии"
        echo "    Покрытие было -$LAST_COV%"
        echo "    Покрытие стало -$COVERAGE%"
        if  awk -v n1="$LAST_COV" -v n2="$COVERAGE" 'BEGIN {exit !(n1 > n2)}'; then
                echo"[!] Покрытие снизилось"
        fi
	echo "$COVERAGE" > "$COVERAGE_FILE"
fi
# Отчет по сборке
BUILD_NUM=1
[ -f "$COUNTER_FILE" ] && BUILD_NUM=$(( $(cat "$COUNTER_FILE") + 1 ))
echo "$BUILD_NUM" > "$COUNTER_FILE"

REPORT_FILE="$REPORTS_DIR/build_report_${DATESTAMP}.txt"
{
    echo "Номер запуска: $BUILD_NUM"
    echo "Версия nginx: $NGINX_VERSION"
    echo "Уникальный номер ревизии: $REVISION"
    echo "Тип сборки: $1"
    echo "Артефакт: ${ARTIFACT_NAME}_amd64.deb" 
    if [ "$1" = "coverage" ]; then
        echo "Отчет о покрытии: coverage_report_$DATESTAMP/index.html"
	echo "Покрытие: $COVERAGE %"
    fi
    
    if [ "$1" != "release" ]; then
        echo "Кэш ccache: $CCACHE_DIR"
    fi
} > "$REPORT_FILE"

# Финальный вывод
echo ""
echo "=============================================="
echo "	СБОРКА УСПЕШНО ЗАВЕРШЕНА!"
echo "=============================================="
echo "    Тип сборки: $1"
echo "    Версия nginx: $NGINX_VERSION"
echo "    Отчёт: $REPORT_FILE"
echo "    Артефакт: $ARTIFACTS_DIR/${ARTIFACT_NAME}_amd64.deb"
if [ "$1" = "coverage" ]; then
        echo "    Отчет о покрытии: coverage_report_$DATESTAMP/index.html"
        echo "    Покрытие: $COVERAGE %"
fi
echo "=============================================="




















