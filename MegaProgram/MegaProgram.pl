#!/usr/bin/perl -w
# EoF 2010
# програмулька для тестирования web-сервера
# v0.02

# TODO
# 

use IO::Socket;
use threads('stack_size' => 32*1024);
use threads::shared;
use Thread::Semaphore;
use Time::HiRes qw(gettimeofday tv_interval);

$#ARGV >= 2 || die "Должно быть 3 аргумента: URL, число потоков, число циклов.\n" .
                   "Например: MegaProgram.pl http://192.168.0.43/File.pdf 15000 10\n";

# ----

($URL, $ThreadCount, $CycleCount, $OutDir) = @ARGV;

my @Threads;

# Разбираем URL
$URL =~ /[http:\/\/]?([\w+\.]+)\:?(\d+)?(\/[\w+\.]+)/;

my $Addr = $1;
my $Port = $2 || "80";
our $Path = $3;

($Addr & $Port & $Path) || die "Неверный URL\n";

my $ServerIP = inet_aton($Addr) || die "Неверный адрес сервера\n";
our $ServerAddress = sockaddr_in($Port,$ServerIP);

# Погнали...
print "Тестируем сервер $Addr\n" . 
      "________________________________________________________________________________\n";

our $StartSem = Thread::Semaphore->new(0);
our $CompleteSem = Thread::Semaphore->new(0);

# Создаем потоки
for ($i = 0; $i < $ThreadCount; $i++) {
	$Threads[$i] = threads->create({'context' => 'list'}, "ThreadSub") || die "Невозможно создать поток";
}
print "Потоков создано: $ThreadCount\n";

# Запускаем потоки
my $FullTime = [gettimeofday];
$StartSem->up($ThreadCount);

# Ждем завершения потоков
$CompleteSem->down($ThreadCount);
$FullTime = tv_interval($FullTime);

# Статистика
my $i;
my $ErrCount = 0;
my @Temp;
my @FullStat;

foreach $Thread (@Threads) {
	@Temp = $Thread->join();
	$ErrCount += pop(@Temp);

	push(@FullStat, @Temp);	
}

# Сумма
my $SumTime = 0;
for ($i = 0; $i <= $#FullStat; $i++) {
	$SumTime += $FullStat[$i];
}

# Среднее время ответа:
my $MidTime = $SumTime / ($#FullStat + 1);

# Среднеквадартическое отклонение
my $Sq = 0;
for ($i = 0; $i <= $#FullStat; $i++) {
	$Sq += ($FullStat[$i] - $MidTime) ** 2;
}

$Sq = sqrt($Sq / ($#FullStat + 1));

print "Тестирование завершено.\n" .
      "Cделано запросов:                " . ($ThreadCount * $CycleCount - $ErrCount) . "\n" .
      "Ошибок:                          $ErrCount\n" .
      "Среднее время ответа:            $MidTime сек.\n" . 
      "Среднеквадратическое отклонение: $Sq сек.\n" .
      "Всего прошло времени:            $FullTime сек.\n" .
      "Запросов в секунду:              " . ($ThreadCount * $CycleCount - $ErrCount) / $FullTime . "\n\n";

print "________________________________________________________________________________\n";


# ---- Функция потоков
sub ThreadSub {
	my @Stats;
	my $Time;	
	my $ErrCount = 0;

	$StartSem->down(1);

	for ($i = 1; $i <= $CycleCount; $i++) {
		unless (eval {
			socket(Socket, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Невозможно создать сокет";
			connect(Socket, $ServerAddress) || die "Невозможно установить соединение";

			# T0
			$Time = [gettimeofday];

			send(Socket, "GET " . $Path . "\n\n", 0);
			@Answer = <Socket>;	

		 	# T1
			$Time = tv_interval($Time);

			close(Socket);

			# Сохраняем ответ	
			if ($OutDir) {
				# Доделать, пока смысла в этом регэкспе вообще нет
				$Path =~ /.?(\/[\w\.]+)/;
				my $OutFile = $OutDir . $1 . " - " . threads->tid() . " - " . $i . " - " . localtime(time);
				open(File, ">$OutFile") || die "Невозможно открыть файл";
				print File @Answer;
				close(File);
			}

			push(@Stats, $Time);
		}) {
			$ErrCount++;
			#print "Houston we have a problem...";
		}		
	}

	$CompleteSem->up(1);

	push(@Stats, $ErrCount);

	return @Stats;
}

