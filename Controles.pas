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

unit Controles;

interface

    uses BaseUnix, Unix, CRT, SysUtils, DateUtils;

    const
        // Es usada para mostrar fecha y hora con el formato correcto.
        numeros: array [0..59] of string = ( '00', '01', '02', '03', '04', '05',
                                             '06', '07', '08', '09', '10', '11',
                                             '12', '13', '14', '15', '16', '17',
                                             '18', '19', '20', '21', '22', '23',
                                             '24', '25', '26', '27', '28', '29',
                                             '30', '31', '32', '33', '34', '35',
                                             '36', '37', '38', '39', '40', '41',
                                             '42', '43', '44', '45', '46', '47',
                                             '48', '49', '50', '51', '52', '53',
                                             '54', '55', '56', '57', '58', '59' );

    type
        proceso = record
                    pid: longint;
                    comando: string;
                    estado: string;
                  end;

        arregloProcesos = array of proceso;
        arregloStrings = array of string;
        arregloDirents = array of dirent;

    var
        // Formato original del texto de la terminal.
        formatoOriginal: byte;

        // Directorio actual de trabajo.
        directorioActual: string;

        // String ingresado luego de prompt.
        entrada: string;

        // Arreglo cuyos elementos son el comando y sus opciones/argumentos.
        comando: arregloStrings;

        // Determina si, luego de un fork, el proceso hijo terminó.
        hijoTerminado: boolean;

        // Cantidad de trabajos ejecutados.
        cantidadProcesos: byte;

        // PID del último proceso ejecutado o detenido.
        ultimoProceso: longint;

        // Lista de todos los trabajos ejecutados.
        listaProcesos: arregloProcesos;


    procedure inicializar();

    // Tratamiento de la entrada.
    procedure leer( var entrada: string );
    function convertir( entrada: string ): arregloStrings;
    function hayOperador( argumentos: arregloStrings ): string;

    // Listado de archivos.
    procedure listarArchivos( lista: arregloDirents; opcion: char );

    // Registro de los procesos.
    procedure agregarProceso( pid: longint; comando: string; estado: string );
    procedure modificarProceso( pid: longint; estado: string );
    function comandoProceso( pid: longint ): string;


implementation

    { procedimiento INICIALIZAR:

        Asigna los valores iniciales de algunas de las variables globales. }

    procedure inicializar();
    begin
        formatoOriginal := textAttr;
        cantidadProcesos := 0;
        ultimoProceso := -1;
    end;


    { procedimiento PROMPT:

        Escribe el prompt en pantalla. }

    procedure prompt();
    var home, usuario: string;
    begin
        // Obtiene el directorio del home, el nombre de usuario y el directorio
        // actual de trabajo.
        home := fpGetEnv( 'HOME' );
        usuario := fpGetEnv( 'USER' );
        getDir( 0, directorioActual );

        textColor( LightMagenta );
        write( usuario + '@' + getHostName() + ' ' );

        textColor( Yellow );

        // Si la ruta del directorio actual comienza en home, reemplaza el
        // principio de la misma por '~'.
        if copy( directorioActual, 1, length( home ) ) = home then
            write( '~' + copy( directorioActual,
                               length( home ) + 1,
                               length( directorioActual ) ) )
        else
            write( directorioActual );

        // Si el usuario es root, muestra '#', de lo contrario muestra '$'.
        if (usuario = 'root') then write(' # ')
        else write(' $ ');

        // Restaura el formato original del texto de la terminal.
        textAttr := formatoOriginal;
    end;


    { función SIN ESPACIOS EXTRAS:

        Devuelve el string de entrada sin espacios de más, es decir, sólo con
        aquellos espacios necesarios (los que separan los comandos, opciones y
        argumentos).

        Ejemplo: '    ls    -l   /home    ' -> 'ls -l /home' }

    function sinEspaciosExtras( entrada: string ): string;
    var posicion: integer;
    begin

        // Quita los espacios que están al principio.
        while entrada[1] = ' ' do
            entrada := copy( entrada, 2, length( entrada ) );

        // Quita los espacios que están al final.
        while entrada[length( entrada )] = ' ' do
            entrada := copy( entrada, 1, length( entrada ) - 1);

        // Si hay dos espacios juntos, devuelve su posición.
        posicion := pos( '  ', entrada );

        // Deja solamente un espacio entre palabras.
        while posicion <> 0 do
        begin
            delete( entrada, posicion, 1 );
            posicion := pos( '  ', entrada );
        end;

        sinEspaciosExtras := entrada;
    end;


    { procedimiento LEER:

        Muestra el prompt y lee un string hasta que éste sea distinto de vacío
        y no sea sólo espacios. Luego le quita los espacios que tenga de más. }

    procedure leer( var entrada: string );
    begin
        repeat
            prompt();
            readLn( entrada );
        until (entrada <> '') and (entrada <> space( length( entrada ) ));

        entrada := sinEspaciosExtras( entrada );
    end;


    { función CONVERTIR:

        Separa el string de entrada en sub-strings de acuerdo a los espacios
        que posea y los guarda en un arreglo.

        Ejemplo: 'ls -l /home/vale' -> ['ls', '-l', '/home/vale'] }

    function convertir( entrada: string ): arregloStrings;
    var argumentos: arregloStrings;
        i: byte;
        posicionEspacio, posicionComilla: integer;
    begin
        // Índice del arreglo.
        i := 0;

        // Establece el tamaño del arreglo.
        setLength( argumentos, i + 1 );

         // Posición del primer espacio (' ') del string.
        posicionEspacio := pos( ' ', entrada );

        // Mientras haya espacios, guarda los strings que estos separan en el arreglo.
        while posicionEspacio <> 0 do
        begin
            // Si se encuentra una comilla, se guarda el string hasta la siguiente comilla.
            if entrada[1] = '"' then
            begin
                delete( entrada, 1, 1 );
                posicionComilla := pos( '"', entrada );
                argumentos[i] := copy( entrada, 1, posicionComilla - 1 );
                entrada := copy( entrada, posicionComilla + 1, length( entrada ) );

                if entrada[1] = ' ' then
                    delete( entrada, 1, 1 );
            end
            // Si no, se guarda hasta el siguiente espacio.
            else
            begin
                argumentos[i] := copy( entrada, 1, posicionEspacio - 1 );
                entrada := copy( entrada, posicionEspacio + 1, length( entrada ) );
            end;

            posicionEspacio := pos( ' ', entrada );

            // Si la entrada no es vacía, aumenta el tamaño del arreglo.
            if entrada <> '' then
            begin
                inc( i );
                setLength( argumentos, i + 1 );
            end;
        end;

        // Si la entrada no es vacía, la guarda como el último argumento.
        if entrada <> '' then
            argumentos[i] := entrada;

        convertir := argumentos;
    end;


    { función HAY OPERADOR:

        Devuelve la posición del operador (|, > o >>) en el arreglo que toma
        como argumento. Devuelve -1 si no lo encontró. }

    function hayOperador( argumentos: arregloStrings ): string;
    var i: byte;
        operador: string;
    begin
        // Índice del arreglo.
        i := 0;

        // Por defecto, sin operador.
        operador := '';

        // Mientras no haya operador y no se acabe el arreglo, busca un operador.
        while (operador = '') and (i <= high( argumentos )) do
        begin
            if (argumentos[i] = '|') or (argumentos[i] = '>') or (argumentos[i] = '>>') then
                operador := argumentos[i]
            else
                inc( i );
        end;

        hayOperador := operador;
    end;


    { procedimiento ORDERNAR POR NOMBRE:

        Ordena alfabéticamente los archivos (dirents*) de un arregloDirents
        según sus nombres.

        * Los dirents son registros que guardan la información de los
        archivos. }

    procedure ordenarPorNombre( var arreglo: arregloDirents );
    var i, j: word;
        auxiliar: dirent;
    begin
        // Ordenamiento burbuja
        for i := 1 to high( arreglo ) do
            for j := 0 to high( arreglo ) - i do
                if upCase( arreglo[j].d_name ) > upCase( arreglo[j+1].d_name ) then
                begin
                    auxiliar := arreglo[j+1];
                    arreglo[j+1] := arreglo[j];
                    arreglo[j] := auxiliar;
                end;
    end;


    { procedimiento COLOR TIPO:

        Establece el color con el que escribir nombre del archivo según su tipo.

        Nota: debe cambiar el color sólo si se está escibiendo en pantalla; de
        escribir en un archivo, puede mostrar caracteres inesperados. }

    procedure colorTipo( archivo: dirent; info: stat );
    begin
        // Si no hay operador, establece el color del texto según el tipo de archivo.
        if hayOperador( comando ) = '' then
        begin
            if fpS_ISLNK( info.st_mode ) then textColor( LightCyan )
            else if fpS_ISDIR( info.st_mode ) then textColor( LightBlue )
            else if fpS_ISREG( info.st_mode ) then
                if pos( '.', archivo.d_name{pChar(@d_name[0])} ) <> 0 then
                    textColor( White )
                else
                    textColor( LightGreen );
        end;
    end;


    { función PERMISOS ARCHIVOS:

        Devuelve un string con los permisos de un archivo respecto a la lectura,
        escritura y ejecución del usuario, el grupo y los demás. }

    function permisosArchivo( mode: mode_t ): string;
    var resultado: string;
    begin
        resultado := '';

        // Permisos del usuario
        if STAT_IRUSR and mode = STAT_IRUSR then resultado := resultado + 'r'
        else resultado := resultado + '-';

        if STAT_IWUSR and mode = STAT_IWUSR then resultado := resultado + 'w'
        else resultado := resultado + '-';

        if STAT_IXUSR and mode = STAT_IXUSR then resultado := resultado + 'x'
        else resultado := resultado + '-';

        // Permisos del grupo
        if STAT_IRGRP and mode = STAT_IRGRP then resultado := resultado + 'r'
        else resultado := resultado + '-';

        if STAT_IWGRP and mode = STAT_IWGRP then resultado := resultado + 'w'
        else resultado := resultado + '-';

        if STAT_IXGRP and mode = STAT_IXGRP then resultado := resultado + 'x'
        else resultado := resultado + '-';

        // Permisos de los demás
        if STAT_IROTH and mode = STAT_IROTH then resultado := resultado + 'r'
        else resultado := resultado + '-';

        if STAT_IWOTH and mode = STAT_IWOTH then resultado := resultado + 'w'
        else resultado := resultado + '-';

        if STAT_IXOTH and mode = STAT_IXOTH then resultado := resultado + 'x'
        else resultado := resultado + '-';

        permisosArchivo := resultado;
    end;


    { procedimiento LISTAR ARCHIVOS:

        Muestra la información de los archivos almacenados en un arregloDirents
        de acuerdo a la opción especificada. }

    procedure listarArchivos( lista: arregloDirents; opcion: char );
    var ano, mes, dia, horas, minutos, segundos, milisegundos: word;
        archivo: stat;
        fecha: TDateTime;
        i, cantidadArchivos: word;
    begin
        case opcion of
            // Muestra todos los archivos no ocultos de forma ordenada y con color.
            '_': begin
                    ordenarPorNombre( lista );

                    // Recorre toda la lista (arreglo) de archivos.
                    for i := 0 to high( lista ) do
                    begin
                        // Si el nombre del archivo no comienza con '.', lo muestra.
                        if lista[i].d_name[0] <> '.' then
                            with lista[i] do
                            begin
                                fpLStat( pChar(@d_name[0]), archivo );  

                                // Establece el color para escribir el nombre.
                                colorTipo( lista[i], archivo );

                                writeLn( pChar(@d_name[0]) );
                            end;
                    end;
                 end;

            // Muestra todos los archivos (incluso los ocultos) de forma ordenada y con color.
            'a': begin
                    ordenarPorNombre( lista );

                    // Recorre toda la lista (arreglo) de archivos.
                    for i := 0 to high( lista ) do
                        with lista[i] do
                        begin
                            fpLStat( pChar(@d_name[0]), archivo );

                            // Establece el color para escribir el nombre.
                            colorTipo( lista[i], archivo );

                            writeLn( pChar(@d_name[0]) );
                        end;
                 end;

            // Muestra todos los archivos (incluso los ocultos) de forma desordenada
            // y sin color.
            'f': for i := 0 to high( lista ) do
                    with lista[i] do writeLn( pChar(@d_name[0]) );

            // Muestra archivos no ocultos de forma ordenada, con color, sus tamaños,
            // permisos y fechas de modificacion. 
            'l': begin
                    ordenarPorNombre( lista );

                    // Establece la cantidad inicial de archivos.
                    cantidadArchivos := 0;

                    // Recorre toda la lista (arreglo) de archivos.
                    for i := 0 to high( lista ) do
                        // Si el nombre del archivo no comienza con '.', lo muestra.
                        if lista[i].d_name[0] <> '.' then
                            with lista[i] do
                            begin
                                fpLStat( pChar(@d_name[0]), archivo );

                                write( archivo.st_size:10 );
                                write( permisosArchivo( archivo.st_mode ):11 );
                                
                                // Obtiene la fecha de modificación y la decodifica.
                                fecha := unixToDateTime( archivo.st_ctime );
                                decodeDate( fecha, ano, mes, dia );
                                decodeTime( fecha, horas, minutos, segundos, milisegundos );

                                write( '  ' );
                                write( numeros[dia], '/', numeros[mes], '/', ano, ' ',
                                       numeros[horas], ':', numeros[minutos], '  ' );

                                // Establece el color para escribir el nombre.
                                colorTipo( lista[i], archivo );

                                writeLn( pChar(@d_name[0]) );

                                // Restaura el formato original del texto de la terminal.
                                textAttr := formatoOriginal;

                                inc( cantidadArchivos );
                            end;

                    writeLn( 'Cantidad de archivos: ', cantidadArchivos );
                 end;
        end;

        // Restaura el formato original del texto de la terminal.
        textAttr := formatoOriginal;
    end;


    { procedimiento AGREGAR PROCESO:

        Agrega un nuevo trabajo al arreglo "listaProcesos" (variable global).
        Esto ocurre cuando un proceso es detenido o ejecutado en segundo plano. }

    procedure agregarProceso( pid: longint; comando: string; estado: string );
    begin
        // Incrementa la cantidad de procesos actuales.
        inc( cantidadProcesos );

        // Aumenta el tamaño de la lista de procesos (arreglo).
        setLength( listaProcesos, cantidadProcesos );

        // Asigna los datos correspondientes al proceso.
        listaProcesos[cantidadProcesos-1].pid := pid;
        listaProcesos[cantidadProcesos-1].comando := comando;
        listaProcesos[cantidadProcesos-1].estado := estado;
    end;


    { procedimiento MODIFICAR PROCESO:

        Cambia el estado de un poceso. Esto ocurre cuando un proceso pasa de estar
        detenido a ejecutarse. }

    procedure modificarProceso( pid: longint; estado: string );
    var i: byte;
    begin
        // Recorre la lista de procesos (arreglo).
        for i := 0 to high( listaProcesos ) do
            // Si lo encuentra, le cambia el estado.
            if listaProcesos[i].pid = pid then
                listaProcesos[i].estado := estado;
    end;


    { función COMANDO PROCESO:

        Devuelve el comando asociado al proceso de PID especificado. }

    function comandoProceso( pid: longint ): string;
    var i: byte;
    begin
        // Recorre la lista de procesos (arreglo).
        for i := 0 to high( listaProcesos ) do
            // Si lo encuentra, devuelve el comando.
            if listaProcesos[i].pid = pid then
                comandoProceso := listaProcesos[i].comando;
    end;
end.    