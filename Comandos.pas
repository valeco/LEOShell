{
    LEOShell - Intérprete de comandos experimental

    Copyright (C) 2015 - Valentín Costa - Leandro Lonardi

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
}

unit Comandos;

{$mode objfpc}

interface

    uses BaseUnix, Unix, CRT, SysUtils, Controles;

    procedure ejecutar( comando: arregloStrings );


implementation

    { procedimiento BG:
        
        Envía a un proceso detenido la señal de continuación (SIGCONT) para que
        continúe su ejecución en segundo plano. Si no se especifica un PID, la
        señal es enviada al último proceso que ha sido detenido.

        En la terminal, el comando es: bg [pid] }

    procedure bg( argumentos: arregloStrings );
    var pid: longint;
    begin
        // Si el comando no posee argumentos, trabaja con el PID del último proceso
        // detenido.
        if high( argumentos ) = 0 then
            pid := ultimoProceso
        else
            // Convierte el string a su valor numérico.
            val( argumentos[1], pid );

        // Si la señal se envía con éxito, modifica el estado del proceso y
        // muestra un mensaje.
        if fpKill( pid, SIGCONT ) = 0 then
        begin
            modificarProceso( pid, 'Ejecutando' );
            writeln( '(', pid, ') ', comandoProceso( pid ), ' &' );
        end
        else
            writeLn( 'No existe el proceso.' )
    end;


    { procedimiento CD:

        Cambia el directorio de trabajo actual utilizando la función fpChDir. Si
        no se especifican argumentos, cambia al directorio home.

        En la terminal, el comando es: cd [directorio] }

    procedure cd( argumentos: arregloStrings );
    begin
        // Si el comando no posee argumentos, cambia el directorio a home.
        if high( argumentos ) = 0 then fpChDir( fpGetEnv( 'HOME' ) )
        else
            // Si el directorio es incorrecto o el cambio no se puede efectuar,
            // muestra un mensaje.
            if fpChDir( argumentos[1] ) = -1 then
                writeLn( 'No existe el directorio.' );
    end;


    { procedimiento CAT:
        
        Concatena uno o dos archivos con la salida estándar.

        En la terminal, el comando es: cat [archivo1] [archivo2] }

    procedure cat( argumentos: arregloStrings );
    var archivo1, archivo2: text;
        texto: string;
    begin
        // Si el comando no posee argumentos, muestra un mensaje.
        if high(argumentos) = 0 then
        begin
            writeLn( 'Debe ingresar al menos un archivo como argumento.' );
            writeLn( 'cat <archivo 1> <archivo 2>' );
        end
        else
        begin
            {$I-}
            assign( archivo1, argumentos[1] );
            reset( archivo1 );
            {$I+}
            
            // Si hay error, muestra un mensaje.
            if IOResult <> 0 then
                writeln( 'No existe el primer archivo.' )
            else
            begin
                // Mientras no llegue al final del archivo, lo lee y lo escribe.
                while not eof( archivo1 ) do
                begin
                    readLn( archivo1, texto );
                    writeLn( texto );
                end;

                close( archivo1 );
            end;

            // Si el comando posee un segundo archivo, trabaja con él.
            if high( argumentos ) = 2 then
            begin           
                {$I-}
                assign( archivo2, argumentos[2] );
                reset( archivo2 );
                {$I+}
                
                // Si hay error, muestra un mensaje.
                if IOResult <> 0 then
                    writeln( 'No existe el segundo archivo.' )
                else
                begin
                    // Mientras no llegue al final del archivo, lo lee y lo escribe.
                    while not eof( archivo2 ) do
                    begin
                        readLn( archivo2, texto );
                        writeLn( texto );
                    end;

                    close( archivo2 );
                end;
            end;

        end;
    end;


    { procedimiento HIJO TERMINÓ:

        Utilizado por externo() para reconocer que el proceso hijo a terminado,
        es decir, que el proceso padre recibió la señal SIGCHLD. }

    procedure hijoTermino( senal: longint ); cdecl;
    begin
        hijoTerminado := true;
    end;


    { procedimiento EXTERNO:
        
        Ejecuta un comando externo y controla la ejecución del mismo, pudiendo
        detenerlo o interrumpirlo. Utiliza fpFork() y fpExecLP() para realizarlo.

        Nota: el uso de la unit CRT provoca que la impresión de los comandos
        externos sea errónea. }

    procedure externo( argumentos: arregloStrings );
    var args: array of ansistring;
        comando: string;
        i: byte;
        pid: longint;
        segundoPlano: boolean;
        tecla: char;
    begin
        // Inicializa tecla para que contenga algún valor.
        tecla := #0;

        // Establece que, al arrancar, el proceso hijo no ha terminado.
        hijoTerminado := false;

        // Almacena el comando "principal" (ej. 'wc', 'yes' o 'ps').
        comando := argumentos[0];

        // Por defecto asume que el comando externo no se ejecuta en segundo plano.
        segundoPlano := false;

        // Recorre los argumentos.
        for i := 1 to high( argumentos ) do
            // Si encuentra un '&', debe ejecutarse en segundo plano.
            if argumentos[i] = '&' then
                segundoPlano := true
            // Si no, guarda como argumento del comando externo.
            else
            begin
                setLength( args, i );
                args[i-1] := argumentos[i];
            end;

        pid := fpFork();

        case pid of
            // En caso de error, muestra un mensaje.
            -1: writeLn( 'Error al crear el proceso hijo.' );

            // Proceso hijo: ejecuta el comando externo.
            0: fpExecLP( comando, args );

        // Proceso padre: controla la ejecución del proceso hijo.
        else
            fpSignal( SIGCHLD, @hijoTermino );

            if segundoPlano then
                // Agrega a la lista de procesos en segundo plano.
                agregarProceso( pid, entrada, 'Ejecutando' )
            else
            begin
                // Mientras no se presione una tecla o termine el proceso hijo,
                // no sigue con la ejecución del código. Esto es necesario para no
                // tener que leer una tecla si el proceso hijo terminó enseguida
                // luego de su ejecución.
                while not (keyPressed() or hijoTerminado) do;

                // Se repite hasta que presione CTRL+Z/CTRL+C o el hijo termine.
                repeat
                    // Si el proceso hijo no termió, lee una tecla.
                    if not hijoTerminado then
                        tecla := readKey();

                    case tecla of
                        // CTRL+C
                        #3: begin
                                // Envía la señal de interrupción.
                                fpKill( pid, SIGINT );
                                // Informa de su interrupción.
                                writeLn( #10 + #13 + 'Proceso interrumpido (', pid, ').' );
                                // Agrega a la lista de procesos en segundo plano.
                                agregarProceso( pid, entrada, 'Terminado' );
                            end;

                        // CTRL+Z
                        #26: begin
                                // Envía la señal de detención.
                                fpKill( pid, SIGSTOP );
                                // Almacena el PID como el último proceso detenido.
                                ultimoProceso := pid;
                                // Informa de su detención.
                                writeLn( #10 + #13 + 'Proceso detenido (', pid, ').' );
                                // Agrega a la lista de procesos en segundo plano.
                                agregarProceso( pid, entrada, 'Detenido' );
                             end;
                    end;
                until (tecla = #3) or (tecla = #26) or hijoTerminado;
            end;

            // Salto de línea necesario para ubicar correctamente el prompt.
            writeln();
        end;
    end;


    { procedimiento FG:
        
        Envía a un proceso detenido la señal de continuación (SIGCONT) para que
        continúe su ejecución en primer plano, siendo posible detenerlo o terminarlo.
        Si no se especifica un PID, la señal es enviada al último proceso que ha sido
        detenido.

        En la terminal, el comando es: fg [pid] }

    procedure fg( argumentos: arregloStrings );
    var pid: longint;
        tecla: char;
    begin
        // Si el comando no posee argumentos, trabaja con el PID del último proceso
        // detenido.
        if high( argumentos ) = 0 then
            pid := ultimoProceso
        else
            // Convierte el string a su valor numérico.
            val( argumentos[1], pid );

        // Si la señal no se envía con éxito, muestra un mensaje.
        if fpKill( pid, SIGCONT ) <> 0 then
            writeLn( 'No existe el proceso.' )
        else
        begin
            // Se repite hasta que presione CTRL+Z o CTRL+C.
            repeat
                tecla := readKey();

                case tecla of
                    // CTRL+C
                    #3: begin
                            // Envía la señal de interrupción.
                            fpKill( pid, SIGINT );
                            // Informa de su interrupción.
                            writeLn( #10 + #13 + 'Proceso interrumpido (', pid, ').' );
                            // Modifica el estado del proceso.
                            modificarProceso( pid, 'Terminado');
                        end;

                    // CTRL+Z
                    #26: begin
                            // Envía la señal de detención.
                            fpKill( pid, SIGSTOP );
                            // Almacena el PID como el último proceso detenido.
                            ultimoProceso := pid;
                            // Informa de su detención.
                            writeLn( #10 + #13 + 'Proceso detenido (', pid, ').' );
                            // Modifica el estado del proceso.
                            modificarProceso( pid, 'Detenido');
                         end;
                end;
            until (tecla = #3) or (tecla = #26);
        end
    end;


    { procedimiento JOBS:

        Muestra la lista de procesos ejecutados en segundo plano, junto con su
        PID, comando asociado y estado actual.

        En la terminal, el comando es: jobs }

    procedure jobs();
    var i: byte;
    begin
        if cantidadProcesos <> 0 then
            for i := 0 to high( listaProcesos ) do
                with listaProcesos[i] do
                    writeLn( '(', pid, ') ', comando, ' <', estado, '>')
        else
            writeLn( 'No hay trabajos.' );
    end;


    { procedimiento KILL:

        Envía una señal a un proceso utilizando la función fpKill(). Si sólo se
        especifica un PID, la señal enviada es la de terminación (SIGTERM).

        En la terminal, el comando es: kill [número de señal] [pid] }

    procedure kill( argumentos: arregloStrings );
    var pid, senal: integer;
    begin
        // Si el comando posee argumentos, muestra un mensaje.
        if high( argumentos ) = 0 then
        begin
            writeln('Debe ingresar un PID y una señal.');
            writeln('kill [número de señal] [pid]');
        end
        else
        begin
            // Si el comando sólo posee un argumento, asume que es un PID y envía
            // la señal de terminación (SIGTERM) al proceso.
            if high( argumentos ) = 1 then
            begin
                // Convierte el string a su valor numérico.
                val( argumentos[1], pid );

                // Si la señal se envía con éxito, muestra un mensaje.
                if fpKill( pid, SIGTERM ) = 0 then
                    writeLn( 'El proceso se ha terminado.' )
                else
                    writeLn( 'No existe el proceso.' )
            end
            else
            begin
                // Convierte los strings a sus valores numéricos.
                val( argumentos[1], senal );
                val( argumentos[2], pid );

                // Si la señal se envía con éxito, muestra un mensaje.
                if fpKill( pid, senal ) = 0 then
                    writeLn( 'Señal enviada.' )
                else
                    writeLn( 'No existe el proceso.' );
            end;
        end;
    end;


    { procedimiento LS:

        Guarda en un arreglo todos los archivos encontrados en el directorio
        especificado para luego listarlos, de acuerdo a la opción pasada como
        argumento (opcional). Si ningún directorio es dado, utiliza el actual.

        En la terminal, el comando es: ls [opción] [directorio] }

    procedure ls( argumentos: arregloStrings );
    var directorio: pDir;
        entrada: pDirent;
        i: word;
        lista: arregloDirents;
        opcion: char;
        ruta: string;
    begin
        // Índice del arreglo.
        i := 1;

        // Ruta a listar por defecto.
        ruta := directorioActual;

        // Recorre los argumentos (arreglo) hasta encontrar una ruta, es decir,
        // un argumento que comience con '/'.
        while (i <= high( argumentos )) and (ruta = directorioActual) do
        begin
            if argumentos[i][1] = '/' then
                ruta := argumentos[i];

            inc( i );
        end;

        // Abre el directorio
        directorio := fpOpenDir( ruta );

        // Tamaño inicial del arreglo.
        i := 0;

        // Agrega todos los archivos del directorio a "lista" (arreglo).
        repeat
            entrada := fpReadDir( directorio^ );

            if entrada <> nil then
            begin
                setLength( lista, i + 1 );
                lista[i] := entrada^;
                inc( i );
            end;
        until entrada = nil;

        // Cierra el directorio.
        fpCloseDir( directorio^ );

        // Índice del arreglo.
        i := 1;

        // Opción por defecto para listar los archivos
        opcion := '_';

        // Recorre los argumentos hasta encontrar una opción, es decir, un
        // argumento que comience con '-'.
        while (i <= high( argumentos )) and (opcion = '_') do
        begin
            // Si es una opción, guarda el segundo caracter (ej. 'a' de '-a').
            if argumentos[i][1] = '-' then
                opcion := argumentos[i][2];

            inc( i );
        end;

        listarArchivos( lista, opcion );
    end;


    { procedimiento TUBERÍA:

        Luego de definir el primer y segundo comando, ejecuta el primero para que
        el resultado del mismo sea utilizado como argumento del segundo, mediante
        un archivo. }

    procedure tuberia( comando: arregloStrings );
    var archivo: ^file;
        i, j: byte;
        nombreArchivo: string;
        primerComando, segundoComando: arregloStrings;
        temporal: longint;
    begin
        // Índice del arreglo del primer comando.
        i := 0;

        // Mientras no encuentre '|', guarda en el arreglo "primerComando".
        while comando[i] <> '|' do
        begin
            setLength( primerComando, i + 1);
            primerComando[i] := comando[i];
            inc( i );
        end;

        // En este punto, "i" contiene el índice donde comienza el segundo comando.
        inc( i );

        // Índice del arreglo del segundo comando.
        j := 0;

        // Mientras no se termine el comando, guarda en el arreglo "segundoComando".
        while i <= high( comando ) do
        begin
            setLength( segundoComando, j + 1);
            segundoComando[j] := comando[i];
            inc( i );
            inc( j );
        end;

        // Nombre del archivo utilizado temporalmente durante la ejecución.
        nombreArchivo := primerComando[0];

        // Crea una variable dinámica a partir del puntero "archivo".
        new( archivo );

        // Asigna el nombre al archivo.
        assign( archivo^, nombreArchivo );

        // Crea y abre el archivo para su escritura.
        reWrite( archivo^ );

        // Almacena temporalmente el identificador de la salida estándar.
        temporal := fpDup( stdOutputHandle );

        // Establece al archivo como salida estándar.
        fpDup2( fileRec( archivo^ ).handle, stdOutputHandle );

        ejecutar( primerComando );

        // Reestablece la salida estándar.
        fpDup2( temporal, stdOutputHandle );

        close( archivo^ );
        fpClose( temporal );

        // Agrega el archivo como argumento.
        setLength( segundoComando, j+1 );
        segundoComando[j] := nombreArchivo;

        ejecutar( segundoComando );

        // Borra el archivo.
        deleteFile( nombreArchivo );
    end;


    { procedimiento PWD:

        Muestra el directorio actual de trabajo.

        En la terminal, el comando es: pwd }

    procedure pwd();
    begin
        writeLn( directorioActual );
    end;


    { procedimiento REDIRECCIÓN:

        Luego de definir el comando, escribe su salida en el archivo especificado
        (si no existe, lo crea), sobreescibiéndolo o agregando al final del mismo,
        según corresponda. }

    procedure redireccion( comando: arregloStrings );
    var archivo: ^text;
        i: byte;
        nombreArchivo, operador: string;
        primerComando: arregloStrings;
        temporal: longint;
    begin
        // Índice del arreglo del primer comando.
        i := 0;
        
        // Mientras no encuentre '|', guarda en el arreglo "primerComando".
        while (comando[i] <> '>') and (comando[i] <> '>>') do
        begin
            setLength( primerComando, i + 1);
            primerComando[i] := comando[i];
            inc( i );
        end;

        // Almacena el operador de redireccionamiento.
        operador := comando[i];

        inc( i );

        // Almacena el nombre del archivo al cual redireccionar la salida.
        nombreArchivo := comando[i];

        // Crea una variable dinámica a partir del puntero "archivo".
        new( archivo );

        // Asigna el nombre al archivo.
        assign( archivo^, nombreArchivo );

        if operador = '>' then
            {$I-}
            // Abre el archivo para escitura y borra su contenido. Si no existe,
            // previamente lo crea.
            reWrite( archivo^ )
            {$I+}
        else
            {$I-}
            // Si existe el archivo, lo abre para escribir al final.
            if fileExists( nombreArchivo ) then
                append( archivo^ )
            // Si no, lo crea y abre para su escritura.
            else
                reWrite( archivo^ );
            {$I+}

        // Almacena temporalmente el identificador de la salida estándar.
        temporal := fpDup( stdOutputHandle );

        // Establece al archivo como salida estándar.
        fpDup2( textRec( archivo^ ).handle, stdOutputHandle );

        // Si hay error, muestra un mensaje.
        if IOResult() <> 0 then
            writeLn( 'Error en la escritura del archivo.' )
        else
        begin
            ejecutar( primerComando );

            // Reestablece la salida estándar.
            fpDup2( temporal, stdOutputHandle );

            close( archivo^ );
            fpClose( temporal );
        end;
    end;


    { procedimiento EJECUTAR:

        Llama al procedimiento correspondiente de acuerdo al comando solicitado,
        pasándole como parámetro el arreglo que contiene los argumentos necesarios
        para su ejecución. }

    procedure ejecutar( comando: arregloStrings );
    begin
        if (hayOperador( comando ) = '>')
            or (hayOperador( comando ) = '>>') then redireccion( comando )
        else if hayOperador( comando ) = '|' then tuberia( comando )
        else if comando[0] = 'bg' then bg( comando )
        else if comando[0] = 'cat' then cat( comando )
        else if comando[0] = 'cd' then cd( comando )
        else if comando[0] = 'fg' then fg( comando )
        else if comando[0] = 'jobs' then jobs()
        else if comando[0] = 'kill' then kill( comando )
        else if comando[0] = 'ls' then ls( comando )
        else if comando[0] = 'pwd' then pwd()
        else externo( comando );
    end;

end.