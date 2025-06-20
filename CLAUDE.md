# rotating-proxy-ng-plus - Проект ротируемых Tor прокси

## Обзор проекта

Это форк оригинального репозитория [rotating-proxy-ng-plus](https://github.com/hackera10/rotating-proxy-ng-plus), созданный для решения проблем с устаревшими зависимостями и утечками памяти. Проект предоставляет легковесное решение для ротации IP-адресов через множественные Tor инстансы.

## Архитектура

### Компоненты системы:

1. **Множественные Tor инстансы**
   - По умолчанию запускается 10 инстансов (настраивается через переменную окружения `tors`)
   - Каждый инстанс работает на своих портах:
     - Tor SOCKS порт: 10000 + id
     - Tor Control порт: 30000 + id
     - HTTP Tunnel порт: 20000 + id (используется для прокси)
   - Конфигурация Tor оптимизирована для быстрой ротации IP:
     - `NewCircuitPeriod 15` - новый circuit каждые 15 секунд
     - `MaxCircuitDirtiness 15` - максимальное время жизни circuit
     - `UseEntryGuards 0` - отключены entry guards для большей анонимности
     - `CircuitBuildTimeout 5` - быстрый таймаут построения circuit

2. **HAProxy балансировщик**
   - Слушает на порту 5566 (основной прокси порт)
   - Использует алгоритм `leastconn` для распределения нагрузки
   - Статистика доступна на порту 4444 по адресу `/haproxy?stats`
   - Настроен внешний health check через скрипт `check_tor.sh`

3. **Ruby управляющий скрипт (start.rb)**
   - Запускает все Tor инстансы с задержкой 2 секунды между запусками
   - Генерирует конфигурацию HAProxy из ERB шаблона
   - Ожидает инициализацию всех инстансов (минимум 120 секунд или 5 секунд на инстанс)

4. **Health check система (check_tor.sh)**
   - Проверяет доступность каждого прокси через curl
   - Автоматически перезапускает сбойные Tor инстансы
   - Логирует все действия в `/var/log/tor_check.log`
   - Использует настраиваемые параметры:
     - `TEST_URL` - URL для проверки (по умолчанию http://icanhazip.com)
     - `PROXY_TIMEOUT` - таймаут проверки (по умолчанию 5 секунд)

## Структура файлов

```
rotating-proxy-ng-plus/
├── Dockerfile           # Alpine Linux based контейнер
├── docker-compose.yml   # Конфигурация для docker-compose
├── start.rb            # Главный управляющий скрипт
├── haproxy.cfg.erb     # Шаблон конфигурации HAProxy
├── check_tor.sh        # Скрипт проверки и перезапуска Tor инстансов
├── torrc              # Конфигурация Tor (опционально)
├── balance.cfg.erb    # Конфигурация балансировщика (не используется)
└── README.md          # Документация проекта
```

## Порты и сервисы

- **5566** - Основной прокси порт (HAProxy frontend)
- **4444** - HAProxy статистика
- **10000-10xxx** - Tor SOCKS порты (внутренние)
- **20000-20xxx** - Tor HTTP Tunnel порты (backend для HAProxy)
- **30000-30xxx** - Tor Control порты

## Использование

### Docker команды:
```bash
# Сборка образа
docker build -t noma4i/rotating-proxy-ng-plus:latest .

# Запуск с 10 Tor инстансами (по умолчанию)
docker run -d -p 5566:5566 -p 4444:4444 noma4i/rotating-proxy-ng-plus

# Запуск с кастомным количеством инстансов
docker run -d -p 5566:5566 -p 4444:4444 --env tors=20 noma4i/rotating-proxy-ng-plus

# Использование docker-compose
docker-compose up -d
```

### Тестирование:
```bash
# Проверка работы прокси
curl --proxy 127.0.0.1:5566 https://api.my-ip.io/v2/ip.json

# Просмотр статистики HAProxy
curl http://localhost:4444/haproxy?stats
```

## Ключевые изменения в форке

1. **Удален Polipo** - заменен на встроенный HTTPTunnelPort в Tor
2. **Оптимизирован Ruby скрипт**:
   - Удалены зависимости `excon` и `parallel`
   - Упрощена логика мониторинга
   - Весь мониторинг передан HAProxy
3. **Добавлен внешний health check**:
   - HAProxy использует `external-check` вместо `tcp-check`
   - Скрипт `check_tor.sh` автоматически перезапускает сбойные инстансы
4. **Улучшена стабильность**:
   - Увеличено время ожидания запуска
   - Добавлены задержки между запусками инстансов
   - Более надежная система перезапуска

## Переменные окружения

- `tors` - количество Tor инстансов (по умолчанию: 10)
- `DEBUG` - включить debug логирование в Ruby скрипте
- `TEST_URL` - URL для проверки прокси (по умолчанию: http://icanhazip.com)
- `PROXY_TIMEOUT` - таймаут проверки прокси в секундах (по умолчанию: 5)

## Особенности и ограничения

- Использует упрощенную конфигурацию Tor без особых функций
- Некоторые Tor соединения могут временно не работать при ротации
- Рекомендуется использовать retry логику в приложении
- HAProxy автоматически исключает неработающие прокси из ротации

## Мониторинг и отладка

- Логи Tor инстансов: через syslog
- Логи HAProxy: через logger в stdout
- Логи health check: `/var/log/tor_check.log`
- Статистика HAProxy: http://localhost:4444/haproxy?stats

## Текущие незакоммиченные изменения

В данный момент в проекте есть несколько модифицированных файлов:
- `Dockerfile` - добавлен `check_tor.sh` и создание необходимых директорий
- `haproxy.cfg.erb` - настроен external-check вместо tcp-check
- `start.rb` - упрощена логика, убран ручной мониторинг прокси
- `check_tor.sh` - новый файл для автоматического health check и перезапуска

Эти изменения улучшают стабильность и автоматизацию системы.