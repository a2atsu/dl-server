local getpid = require('process').getpid;
local signal = require('signal');
local InetServer = require('net.stream.inet.server')
local sentry = require('sentry').default()
--local HOST = '127.0.0.1';
local HOST = '10.1.1.16';
local PORT = '1235';
local RUNNING = false;
local clients = {};
local server, err;

function fsize(file)
  local current = file:seek();
  local size = file:seek("end");
  file:seek("set",current);
  return size
end

local function close( sock )
    -- unwatch all events
    for i = 1, #sock.evts do
        sock.evts[i]:unwatch();
    end
    -- close socket
    sock:close();
end

local function download( client, file)
    local fh = io.open(file,"rb");
    local block = 2^13;
    if fh then
      print(fsize(fh));
      while true do
        local byte = fh:read(block);
        if byte == nil then
          break;
        else
          local len, err, again = client:send(byte);
          while (again==true) do
            local left = block - len;
            local len1;
            if (left > 0) then
              local newbyte=string.sub(byte,len+1);
              len1, err, again = client:send(newbyte);
              len = len+len1;
            else
              break;
            end
          end
        end
      end
      fh:close();
      --close( client );
    else
    print("no such file")
    end
end

local function onRecv( client, ishup )
    if ishup then
        print( 'onRecv: closed by peer' );
        close( client );
    else
        local data, err, again = client:recv();
        if not again then
            if err then
                print( 'onRecv: recv error', err );
                close( client );
            elseif not data then
                print( 'closed by peer' );
                close( client );
            else
                print( ('received: %q'):format( data ) ); --receive filename
                download(client,data);
--[[                local fh = io.open(data,"rb");
                local block = 2^13;
                if fh then
                  print(fsize(fh));
                  while true do
                    local byte = fh:read(block);
                    if byte == nil then
                      break;
                    else
                      local len, err, again = client:send(byte);
                      while (again==true) do
--                        print(('block:%d len:%d'):format(block,len));
                        local left = block - len;
                        local len1;
                        if (left > 0) then
                          local newbyte=string.sub(byte,len+1);
                          len1, err, again = client:send(newbyte);
                          len = len+len1;
                        else
                          break;
                        end
                      end  --while again=true
                    end -- if byte
                  end --while true
                  fh:close();
--]]
                  for i, cand_client in ipairs( clients ) do 
                    print(i);
                    print(("i: %d, client: %s"):format(i, cand_client));
                    print(("cand_client:%s, client:%s"):format(cand_client,client));
                    if cand_client==client then
                      clients[i]=null;
                      close( client );
                      table.remove(clients, i);
                      print(("onRecv:called close: %d, %s"):format(i,client));
                    end
              --    end
                end
            end
        end
        --0502 client:close();
    end
end


local function onAccept()
    local client, err = server:accept();

    print( "onAccept")
    if err then
        print( 'accept error: ', err );
    elseif client then
        --client.evts, err = sentry:newevents( 2 );
        client.evts, err = sentry:newevents( 1 );
        print("onAccept:");
        print(client);
        -- register readable event
        err = err or client.evts[1]:asreadable( client:fd(), function( ... )
             onRecv( client, ... );
        end);
-- or 
       --       client.evts[2]:aswritable( client:fd(), function( ... ) onSend( client, ... ); end);
        if err then
            print( err );
            client:close();
        else
            table.insert(clients, client);
            print( ('onAccept size of clients:[%d]'):format(#clients) );
            print(table.getn(clients));
        end
    end
end


local function onHUP()
    print( 'got SIGHUP' ); 
    print( ('size of clients:[%d]'):format(#clients) );
    for i, client in ipairs( clients ) do --broadcasting FIN
          print(i);
          print(client);
          print(("onHUP:called close: %d, %s"):format(i,client));
          if not client then
	    client:closew();
          end
    end
--    clients = {}; --clear array
    print( ('onHUP: size of clients:[%d]'):format(#clients) );
end


local function runloop()
    local nevt, ev, evtype, ishup, err;

    print( ('start server[%d] at %s:%s'):format( getpid(), HOST, PORT ) );
    RUNNING = true;

    while #sentry > 0 and RUNNING == true do
        -- wait forever
        nevt, err = sentry:wait( -1 );

        -- got critical error
        if err then
            print( err );
            break;
        -- consume occurred events
        elseif nevt > 0 then
            ev, evtype, ishup, fn = sentry:getevent();
            while ev do
                ok, err = pcall( fn, ishup );
                if not ok then
                    print( 'invocation error: ', err );
                    RUNNING = false;
                    break;
                end
                ev, evtype, ishup, fn = sentry:getevent();
            end
        end
    end
    RUNNING = false;
    print( 'stop server' );

end


-- block all signals
signal.blockAll();
-- unblock SIGINT (CTRL+C)
signal.unblock( signal.SIGINT );

-- create server socket
server, err = InetServer.new({
    host = HOST,
    port = PORT,
    reuseaddr = true,
    reuseport = true,
    nonblock = true
});
err = err or server:listen();
if err then
    error( err );
end

-- set tcpnodelay option
server:tcpnodelay( true );


-- create 2 event listener
server.evts, err = sentry:newevents( 2 );
-- register signal HUP and readableevents
err = err or
      server.evts[1]:assignal( signal.SIGHUP, onHUP ) or
      server.evts[2]:asreadable( server:fd(), onAccept );
if err then
    error( err );
end

runloop();

