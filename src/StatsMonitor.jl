module StatsMonitor

using Sockets
using Statistics
using Dates
using JSON3

#-----------------------------------------------------------------------# utils
init_buckets() = Dict{Symbol, Any}()

q5(x) = quantile(x, [0, .25, .5, .75, 1])

function get_stat(s::Symbol)
    s == :mean      && return mean
    s == :max       && return maximum
    s == :min       && return minimum
    s == :extrema   && return extrema
    s == :median    && return median
    s == :sum       && return sum
    s == :q5        && return q5
    return error("Unrecognized statistic")
end

#-----------------------------------------------------------------------# Backend
abstract type Backend end

struct TerminalBackend <: Backend end

#-----------------------------------------------------------------------# Config
struct Config{B <: Backend}
    port::Int
    backend::B
    interval::Int
end
function Config(;port=8125, backend=TerminalBackend(), interval=1)
    Config(port, backend, interval)
end

function flush!(buckets, c::Config{TerminalBackend})
    println("Heartbeat: $(now())")
    println(Dict(k => (n = length(v[1]), stat=v[2], result=v[2](v[1])) for (k,v) in pairs(buckets)))
    empty!(buckets)
end


#-----------------------------------------------------------------------# tcp_server
# expects message like: """{ "my_id": { "mean": $(randn()) } }"""
function tcp_server(c::Config = Config())
    server = listen(c.port)
    buckets = init_buckets()
    timer = Timer(_ -> flush!(buckets, c), 1, interval=c.interval)
    while true
        sock = accept(server)
        @async while isopen(sock)
            js = JSON3.read(readline(sock))
            for (k, v) in pairs(js)
                if haskey(buckets, k)
                    push!(buckets[k].data, first(values(v)))
                else
                    for (k2, v2) in pairs(v)
                        setindex!(buckets, (data=[v2], stat=get_stat(k2)), k)
                    end
                end
            end
        end
    end
    close(timer)
    close(server)
end


# using Sockets
# using Statistics
# using JSON3
# using Dates
# using OnlineStatsBase

# #-----------------------------------------------------------------------# Terms
# # - A "bucket" maps an ID (Symbol) to an "aggregator"
# # - A "backend" is where the aggregated values are sent to.

# #-----------------------------------------------------------------------# init_bucket
# # id => (agg_type => bucket)
# init_buckets() = Dict{Symbol, Pair{Symbol, OnlineStat}}()

# # fallbacks are for OnlineStats
# add_to_bucket!(bucket, y) where {T} = fit!(last(bucket), y)
# apply_agg(bucket)  = bucket

# function init_bucket(s::Symbol)
#     s === :m && return :m => Mean()
#     s === :s && return :s => Sum()
#     s === :c && return :c => Counter()
#     s === :e && return :e => Extrema()
#     return @error "well that shouldn't have happened"
# end

# #-----------------------------------------------------------------------# Backend
# abstract type Backend end

# struct Terminal <: Backend end
# function send(out, backend::Terminal)
#     println("timestamp: ", Dates.format(now(), "yyyymmddTH:M:S"))
#     for (k, v) in pairs(out)
#         println("  > $k: $v")
#     end
# end

# #-----------------------------------------------------------------------# Config
# struct Config{B <: Backend, T}
#     port::Int
#     buckets::T
#     backend::B
#     interval::Int
# end
# function Config(;port=8125, buckets=init_buckets(), backend=Terminal(), interval=1)
#     Config(port, buckets, backend, interval)
# end

# function flush!(c::Config)
#     send(c.buckets, c.backend)
#     empty!(c.buckets)
# end

# #-----------------------------------------------------------------------# UDP
# function udp_server(opts::Config = Config())
#     sock = UDPSocket()
#     bind(sock, ip"127.0.0.1", opts.port)
#     timer = Timer(t -> flush!(opts), 1, interval=opts.interval)
#     while true
#         handle_message!(opts.buckets, recv(sock))
#     end
#     close(timer)
#     close(sock)
# end

# #-----------------------------------------------------------------------# TCP
# # broken
# function tcp_server(opts::Config = Config())
#     server = listen(opts.port)
#     timer = Timer(t -> flush!(opts), 1, interval=opts.interval)
#     while true
#         sock = accept(server)
#         @async while isopen(sock)
#             handle_message!(opts.buckets, sock.buffer)
#         end
#     end
#     close(timer)
#     close(server)
# end

# #-----------------------------------------------------------------------# ZMQ
# # broken
# function zmq_server(opts::Config = Config())
#     sock = Socket(SUB)
#     @info "Binding SUB Socket to $(opts.port)"
#     bind(sock, "tcp://*:$(opts.port)")
#     timer = Timer(t -> flush!(opts), 1, interval=opts.interval)
#     while true
#         try
#             msg = recv(sock, String)
#             handle_message!(opts.buckets, msg)
#         catch err
#             @warn err
#         end
#     end
#     close(timer)
#     close(sock)
# end

# #-----------------------------------------------------------------------# handle_message!
# function handle_message!(buckets, msg)
#     for (k, v) in pairs(JSON3.read(msg))
#         bucket_type, value = first(v)
#         add_to_bucket!(get!(buckets, k, init_bucket(bucket_type)), value)
#     end
# end

end # module
