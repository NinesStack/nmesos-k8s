#!/bin/sh
MYSELF=`which "$0" 2>/dev/null`
[ $? -gt 0 -a -f "$0" ] && MYSELF="./$0"
java=java
if test -n "$JAVA_HOME"; then
    java="$JAVA_HOME/bin/java"
fi
exec "$java" \
	-Xmx64m -Xms64m \
	-XX:+TieredCompilation \
	-XX:TieredStopAtLevel=1 \
	-Djruby.compile.invokedynamic=false \
	-Djruby.compile.mode=OFF \
	-noverify $java_args -jar $MYSELF "$@"
exit 1 
