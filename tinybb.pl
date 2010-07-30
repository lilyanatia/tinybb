#!/usr/bin/perl

use Fcntl qw(:flock);
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Encode qw(decode);
use encoding 'utf8';
use open ':utf8';

use constant BOARD_TITLE => 'anonymous bbs';

my $script = $ENV{SCRIPT_NAME};

make_index() && redirect() unless $ENV{REQUEST_METHOD} =~ /^post$/i;

my $req = new CGI;

my $thread = $req->param('thread');
my $title = $req->param('title');
my $comment = $req->param('comment');
my $sage = $req->param('sage');
my $permasaged;
my $deleted;
my $postcount;

die 'HAX' if $thread =~ /[^0-9]/;
$title = clean_string($title);
$script =~ s/%/%25/g;
$script =~ s/"/%22/g;
$script =~ s/</%3c/g;
$script =~ s/>/%3e/g;
$comment = clean_string($comment);
die 'no comment entered' unless $comment;
die 'comment too long' if length $comment > 8192;

if(!$thread){
 die 'no title entered' unless $title;
 $thread = time;
 open THREADS, ">>threads.txt";
 flock THREADS, LOCK_EX;
 print THREADS "$thread 1 0 0 $title\n";
 flock THREADS, LOCK_UN;
 close THREADS;
 $postcount = 1;
 open THREAD, ">>res/${thread}.html";
 flock THREAD, LOCK_EX;
 my $index = $script;
 $index =~s/\/[^\/]*$/\//;
 print THREAD "<!DOCTYPE html><html><head><title>$title</title>",
  "<link rel=\"stylesheet\" type=\"text/css\" href=\"../style.css\"></head>",
  "<body class=\"threadpage\"><p><a href=\"$index\">return</a></p>",
  "<hr><h1>$title</h1>\n",
  "<form action=\"$script\" method=\"post\">",
  "<p><input type=\"hidden\" name=\"thread\" value=\"$thread\">",
  "<input type=\"checkbox\" name=\"sage\" checked=\"checked\"> don't bump ",
  "thread <input type=\"submit\" value=\"submit\"></p>",
  "<p><textarea name=\"comment\" rows=\"6\" cols=\"60\"></textarea></p>",
  "</form></body></html>\n";
 flock THREAD, LOCK_UN;
 close THREAD;
}else{
 my $found = 0;
 my @threads;
 open THREADS, "<threads.txt";
 flock THREADS, LOCK_SH;
 for(<THREADS>){
  if(/^([0-9]+) ([0-9]+) ([01]) ([01]) (.*)$/){
   if($1 eq $thread){
    $found = 1;
    ($postcount, $permasaged, $deleted, $title) = ($2 + 1, $3, $4, $5);
    redirect() if $postcount > 1000;
    push @threads, "$thread $postcount $permasaged $deleted $title\n" if $sage or $permasaged or $deleted;
   }else{
    push @threads, $_;
   }
  }
 }
 flock THREADS, LOCK_UN;
 close THREADS;
 die 'thread does not exist' unless $found;
 push @threads, "$thread $postcount 0 0 $title\n" unless $sage or $permasaged or $deleted;
 open THREADS, ">threads.txt";
 flock THREADS, LOCK_EX;
 print THREADS @threads;
 flock THREADS, LOCK_UN;
 close THREADS;
}

open THREAD, "<res/${thread}.html";
flock THREAD, LOCK_SH;
my @thread = <THREAD>;
flock THREAD, LOCK_UN;
close THREAD;
my $lastline = pop @thread;
$lastline = "<p>this thread has 1000 posts. you cannot post in it anymore.</p></body></html>\n" if $postcount >= 1000;
push @thread, "<div class=\"post\" id=\"$thread:$postcount\"><div class=\"postnum\">$postcount</div>".
 "<div class=\"postdate\">". scalar gmtime.
 "</div><div class=\"postbody\">".
 format_comment($comment, $thread). "</div></div>\n", $lastline;
open THREAD, ">res/${thread}.html";
flock THREAD, LOCK_EX;
print THREAD @thread;
flock THREAD, LOCK_UN;
close THREAD;

make_index() and redirect();

sub clean_string($){
 my($str)=@_;
 $str=decode('utf8',$str);
 $str=~s/&/&amp;/g;
 $str=~s/</&lt;/g;
 $str=~s/>/&gt;/g;
 $str=~s/"/&quot;/g;
 $str=~s/[\x00-\x08\x0b\x0c\x0e-\x1f\x80-\x84]//g; # control chars
 $str=~s/[\x{d800}-\x{dfff}]//g; # surrogate code points
 $str=~s/[\x{202a}-\x{202e}]//g; # text direction
 $str=~s/[\x{fdd0}-\x{fdef}\x{fffe}\x{ffff}\x{1fffe}\x{1ffff}\x{2fffe}\x{2ffff}\x{3fffe}\x{3ffff}\x{4fffe}\x{4ffff}\x{5fffe}\x{5ffff}\x{6fffe}\x{6ffff}\x{7fffe}\x{7ffff}\x{8fffe}\x{8ffff}\x{9fffe}\x{9ffff}\x{afffe}\x{affff}\x{bfffe}\x{bffff}\x{cfffe}\x{cffff}\x{dfffe}\x{dffff}\x{efffe}\x{effff}\x{ffffe}\x{fffff}]//g; # non-characters
 $str=join('',map{$_<0x10fffe?$_:''}split(//,$str));
 return $str;
}

sub format_comment($$){
 my($comment, $thread) = @_;
 my $index = $script;
 $index =~s/\/[^\/]*$/\//;
 $comment =~s/&gt;&gt;([0-9]+)/<a href="${index}res\/${thread}.html#$thread:$1">&gt;&gt;$1<\/a>/g;
 $comment =~s/^(&gt;.*)$/<blockquote>$1<\/blockquote>/mg;
 $comment =~s/\r\n/<br>/gs;
 $comment =~s/\r/<br>/gs;
 $comment =~s/\n/<br>/gs;
 $comment =~s/<\/blockquote><br><blockquote>/<br>/g;
 return $comment;
}

sub redirect{
 my $index = $script;
 $index =~s/\/[^\/]*$/\//;
 print "Status: 302 Go West\nLocation: $index\n\n";
 exit;
}

sub make_index{
 open INDEX, ">index.html";
 flock INDEX, LOCK_EX;
 print INDEX "<!DOCTYPE html>\n<html lang=\"en\">\n",
  "<head><title>" . BOARD_TITLE . "</title>\n",
  "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"></head>\n",
  "<body id=\"mainpage\">\n<div id=\"titlebox\"><span id=\"title\">",
  "<span style=\"color:#060\">" . BOARD_TITLE . "</span></span></div>\n",
  "<div id=\"threadbox\">\n";
 open THREADS, "<threads.txt";
 flock THREADS, LOCK_SH;
 my @threads = reverse <THREADS>;
 flock THREADS, LOCK_UN;
 close THREADS;
 my $i = 0;
 my @threads_index = 0..($#threads > 39 ? 39 : $#threads);
 for(@threads[@threads_index]){
  ++$i;
  /^([0-9]+) ([0-9]+) ([01]) ([01]) (.*)$/;
  my ($thread, $postcount, $permasaged, $deleted, $title) = ($1, $2, $3, $4, $5);
  print INDEX "<a href=\"res/${thread}.html\">$i:</a> <a href=\"",
   $i < 11 ? "#$thread" : "res/${thread}.html",
   "\">$title ($postcount)</a>\n" if $thread and !$deleted;
 }
 print INDEX '<div class="threadboxlinks"><a href="subback.html">all threads</a>',
  ' <a href="#threadform">new thread</a></div></div>',"\n",
  "<div class=\"threads\">\n";
 @threads_index = 0..($#threads > 9 ? 9 : $#threads);
 for(@threads[@threads_index]){
  /^([0-9]+) ([0-9]+) ([01]) ([01]) (.*)$/;
  my ($thread, $postcount, $permasaged, $deleted, $title) = ($1, $2, $3, $4, $5);
  if($thread and !$deleted){
   print INDEX "<div class=\"thread\" id=\"$thread\">\n<h1>$title</h1>\n";
   open THREAD, "<res/${thread}.html";
   flock THREAD, LOCK_SH;
   my @posts = <THREAD>;
   flock THREAD, LOCK_UN;
   close THREAD;
   shift @posts;
   pop @posts;
   my @post_index = @posts > 9 ? (0, ($#posts - 8)..$#posts) : 0..9;
   print INDEX $_ for @posts[@post_index];
   print INDEX "<form action=\"$script\" method=\"post\">\n",
    "<p><input type=\"hidden\" name=\"thread\" value=\"$thread\">",
    "<input type=\"checkbox\" name=\"sage\" checked=\"checked\"> ",
    "don't bump thread <input type=\"submit\" value=\"submit\"></p>\n",
    "<p><textarea name=\"comment\" rows=\"6\" cols=\"60\"></textarea></p>\n",
    "</form>\n" if @posts < 1000;
   print INDEX
    "<p>this thread has 1000 posts. you cannot post in it anymore.</p>\n"
    if @posts == 1000;
   print INDEX "<p><a href=\"res/${thread}.html\">entire thread</a></p></div>\n";
  }
 }
 print INDEX "</div>\n",
  "<form action=\"$script\" method=\"post\" id=\"threadform\">\n",
  "<p>title: <input type=\"text\" name=\"title\"> <input type=\"submit\" value=\"submit\"></p>\n",
  "<p><textarea name=\"comment\" rows=\"6\" cols=\"60\"></textarea></p>\n",
  "</form></body></html>\n";
 flock INDEX, LOCK_UN;
 close INDEX;
 my $index = $script;
 $index =~s/\/[^\/]*$/\//;
 open SUBBACK, ">subback.html";
 flock SUBBACK, LOCK_EX;
 print SUBBACK "<!DOCTYPE html>\n<html lang=\"en\">\n",
  "<head><title>" . BOARD_TITLE . "</title>\n",
  "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"></head>\n",
  "<body id=\"subback\">\n",
  "<p><a href=\"$index\">return</a></p>\n",
  "<ol id=\"threadlist\">\n";
 for(@threads){
  /^([0-9]+) ([0-9]+) ([01]) ([01]) (.*)$/;
  my ($thread, $postcount, $permasaged, $deleted, $title) = ($1, $2, $3, $4, $5);
  if($thread and !$deleted){
   print SUBBACK "<li><a href=\"res/${thread}.html\">$title ($postcount)</a></li>\n";
  }
 }
 print SUBBACK "</ol></body></html>\n";
 flock SUBBACK, LOCK_UN;
 close SUBBACK;
}
