using SimpleFileServer
using Logging
@Logging.configure(level=DEBUG)
using Base.Test

mktempdir()do d1
    mktempdir() do d2
        name, handle = mktemp(d2)
        orig = Mmap.mmap(handle, Array{UInt8, 1}, 1000)
        rand!(orig)
        Mmap.sync!(orig)



        fn = "file"
        to = "$d2/file"
        @async SimpleFileServer.start(8080,d1, ()->())
        client = SimpleFileServer.Client.make("localhost", 8080)



        
        f = SimpleFileServer.Client.upload(client, fn, orig )
        @info "Upload Completed using mmap"
        @debug f
        dl = SimpleFileServer.Client.download(client, fn, to)
        @test orig == dl
        @info "Full Download Correct"
        dl = SimpleFileServer.Client.download(client, fn, to, 10, 10)
        @test orig[10:20] == dl
        @info "Partial Download Correct"
        @debug SimpleFileServer.Client.delete(client, fn)
        rm(to)
        @info "File Deleted"
        err = @test_throws Base.UVError SimpleFileServer.Client.delete(client, fn)
        @info "Double Delete Fails"
        @info err
        err = @test_throws Base.UVError SimpleFileServer.Client.download(client, fn, to)
        @info err
        @info "Missign Download Fails"
        
        f = SimpleFileServer.Client.upload(client, fn, ASCIIString(name))
        @info "Upload Completed using file name, missing download did not re-create file"
        dl = SimpleFileServer.Client.download(client, fn, to)
        
        
    end
    
end

