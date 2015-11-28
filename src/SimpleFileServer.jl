module SimpleFileServer
export File
using Logging
using SHA

@Logging.configure(level=DEBUG)
immutable File
    name::ASCIIString
    hash::ASCIIString
    size::Int64
end
abstract FileCommand

# TODO: is this really safe?
function safePath(f::Function,dirname::ASCIIString, path::ASCIIString)
    if contains(path, "..")
        throw(ErrorException("Path not allowed to contain '..'"))
    elseif contains(path, "~")
        throw(ErrorException("Path not allowed to contain '~'"))
    elseif startswith(path, "/") || endswith(path, "/")
        throw(ErrorException("Path not allowed to start or end with '/'"))

    else
        joinpath(dirname, path)|> f
    end
end

type Download <: FileCommand
    name::ASCIIString
    n_bytes_offset::Nullable{Tuple{Integer,Integer}}
end
type Delete <: FileCommand
    name::ASCIIString
end
type Upload <: FileCommand
    f::File
end

function HandleFileCommand(conn, args::Download, base::AbstractString)
    safePath(base, args.name) do path
        try
            if isfile(path)
                a = if isnull(args.n_bytes_offset)
                    Mmap.mmap(path, Array{UInt8,1})
                else
                    n_bytes, offset = args.n_bytes_offset.value
                    # TODO figure out right way to do this
                    Mmap.mmap(path, Array{UInt8,1})[n_bytes:offset+n_bytes]
                end

                serialize(conn, length(a))
                write(conn, a)
            else
                serialize(conn, -1)

            end
        catch err
            #TODO Don't use this -- what's a better solution thought?
            serialize(conn, -1)
        finally
            flush(conn)
        end
    end
end
function HandleFileCommand(conn, args::Delete, base::AbstractString)
    try
        safePath(base, args.name) do path
            @debug path
            rm(path)
        end
        serialize(conn, Nullable())
    catch err
        serialize(conn, Nullable(err))
    end
end
function HandleFileCommand(conn, up::Upload, base::AbstractString)
    args = up.f
    safePath(base, args.name) do path
        if length(args.hash) != 64
            serialize(conn,Nullable(ErrorException("Malformed Hash")))
        elseif isfile(path)
            serialize(conn,Nullable(ErrorException("File Already Exists")))
        end
        open(path, "w+") do f
            a = Mmap.mmap(f, Array{UInt8, 1}, args.size)
            readbytes!(conn, a, args.size)
            Mmap.sync!(a)
        end
        if SHA.sha256(open(path)) != args.hash
            rm(path)
            serialize(conn,Nullable(ErrorException("File did not Hash Properly")))
        end
        serialize(conn,Nullable{ErrorException}())
    end
end

function start(port::Int64, base::AbstractString, setup::Function)
    base = base |>  expanduser |> realpath # Need to get rid of links
    @info "Starting SimpleFileServer on port $port in path $base"
    server = listen(port)
    setup()
    while  true
        conn = accept(server)
        @debug "SimpleFileServer on $port has an incoming connection"
        @async begin
            try
                args = deserialize(conn)::FileCommand
                @debug args
                try
                    HandleFileCommand(conn, args, base)
                catch err
                    @debug "Error While Handling: $err"
                end
            catch err
                @debug "Error While Deserializing : $err"
            finally 
                close(conn)
            end
        end
    end
end

function main()
    port = parse(Int64, ARGS[1])
    base = args[2]
    
    start(port, base)
end

module Client
using SHA
using SimpleFileServer: Upload, Download, Delete, File
using Logging
@Logging.configure(level=DEBUG)
export make, download, upload, delete
immutable t
    host::AbstractString
    port::Int64
end
@inline function make(host::AbstractString, port::Int64)
    t(host, port)
end
@inline function t_connect(c::t)
    connect(c.host, c.port)
end
function download(client::t, name::ASCIIString, to::ASCIIString, n_bytes_offset::Nullable{Tuple{Int64, Int64}})
    conn = t_connect(client)
    serialize(conn, Download(name,n_bytes_offset))
    flush(conn)
    s =deserialize(conn)
    if s == -1
        throw(Base.UVError("Remote Server $(client.host):$(client.port)", Base.UV_ENOENT))
    elseif s == 0
        touch(to)
        Array(UInt8, 0)
    else
        m = Mmap.mmap(open(to, "w+"), Array{UInt8, 1}, s)
        readbytes!( conn, m, typemax(Int64))
        Mmap.sync!(m)
        m
    end
end
download(client::t, name::ASCIIString, to::ASCIIString, n_bytes::Integer, offset::Integer)= download(client, name, to, Nullable((n_bytes,offset)))
download(client::t, name::ASCIIString, to::ASCIIString)= download(client, name, to, Nullable{Tuple{Int64, Int64}}())
function upload(c::t, f::File, m::Array{UInt8,1})
    conn = t_connect(c)
    serialize(conn, Upload(f))
    b =write(conn, m)
    flush(conn)
    @info "Uploading wrote $(b) bytes"
    m_err = deserialize(conn)
    if !isnull(m_err)
        throw(m_err.value)
    end
    close(conn)
end

function upload(c::t, name::ASCIIString,m::Array{UInt8, 1})
    f = File(name, SHA.sha256(m), length(m))
    upload(c, f, m)
    f
end
function upload(c::t, name::ASCIIString, path::ASCIIString)
    open(path, "r+") do f
        m = Mmap.mmap(f, Array{UInt8,1})
        upload(c, name, m)
    end
end
function delete(c::t, name::ASCIIString)
    conn = t_connect(c)
    serialize(conn, Delete(name))
    flush(conn)
    m_err = deserialize(conn)
    if !isnull(m_err)
        throw(m_err.value)
    end
end
end
end # module

