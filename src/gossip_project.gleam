import actor
import topology
import gleam/erlang/process

@external(erlang, "init", "get_plain_arguments")
fn get_args() -> List(String)

@external(erlang, "erlang", "system_time")
fn get_current_time_nanos() -> Int

@external(erlang, "timer", "sleep")
fn sleep(milliseconds: Int) -> Nil

@external(erlang, "string", "trim")
fn trim_string(s: String) -> String

@external(erlang, "unicode", "characters_to_list")
fn string_to_charlist(s: String) -> List(Int)

@external(erlang, "io", "format")
fn print(text: String) -> Nil

@external(erlang, "erlang", "integer_to_list")
fn int_to_string(value: Int) -> String

// FIXED: Proper time calculation
fn get_current_time_millis() -> Int {
  get_current_time_nanos() / 1000000  // Convert nanoseconds to milliseconds
}

pub type SimulationResult {
  SimulationResult(
    converged: Int,
    total: Int,
    rounds: Int
  )
}


pub fn main() {
  let args = get_args()
  case args {
    [num_nodes_str, topology_str, algorithm_str] -> {
      case parse_int(trim_string(num_nodes_str)) {
        Ok(num_nodes) -> {
          let clean_topology = trim_string(topology_str)
          let clean_algorithm = trim_string(algorithm_str)
          
          print("DEBUG: Cleaned - Nodes: ")
          print(int_to_string(num_nodes))
          print(", Topology: '")
          print(clean_topology)
          print("', Algorithm: '")
          print(clean_algorithm)
          print("'\n")
          
          case validate_inputs(num_nodes, clean_topology, clean_algorithm) {
            Ok(_) -> {
              print("=== Gossip Protocol Simulation ===\n")
              print("Nodes: ")
              print(int_to_string(num_nodes))
              print(", Topology: ")
              print(clean_topology)
              print(", Algorithm: ")
              print(clean_algorithm)
              print("\n")
              
              let start_time = get_current_time_millis()
              let result = run_complete_simulation(num_nodes, clean_topology, clean_algorithm)
              let end_time = get_current_time_millis()
              print_results(result, end_time - start_time)
            }
            Error(error_msg) -> {
              print("ERROR: ")
              print(error_msg)
              print("\n")
            }
          }
        }
        Error(_) -> print("ERROR: Invalid number of nodes. Must be a positive integer.\n")
      }
    }
    _ -> {
      print("USAGE: gleam run -- <numNodes> <topology> <algorithm>\n")
      print("  numNodes: Number of actors (positive integer)\n")
      print("  topology: full, 3D, line, or imp3D\n")
      print("  algorithm: gossip or push-sum\n")
      print("EXAMPLE: gleam run -- 10 full gossip\n")
    }
  }
}

// KEEPING YOUR WORKING PARSE_INT FUNCTION
fn parse_int(s: String) -> Result(Int, Nil) {
  parse_int_helper(string_to_charlist(s), 0, 1)
}

fn parse_int_helper(chars: List(Int), acc: Int, sign: Int) -> Result(Int, Nil) {
  case chars {
    [] -> Ok(acc * sign)
    [45, ..rest] -> parse_int_helper(rest, acc, -1)
    [char, ..rest] -> case char >= 48 && char <= 57 {
      True -> parse_int_helper(rest, acc * 10 + {char - 48}, sign)
      False -> Error(Nil)
    }
  }
}

fn validate_inputs(num_nodes: Int, topology: String, algorithm: String) -> Result(Nil, String) {
  case num_nodes <= 0 {
    True -> Error("Number of nodes must be positive")
    False -> case validate_topology(topology) {
      False -> Error("Invalid topology. Use: full, 3D, line, or imp3D")
      True -> case validate_algorithm(algorithm) {
        False -> Error("Invalid algorithm. Use: gossip or push-sum")
        True -> Ok(Nil)
      }
    }
  }
}

fn validate_topology(topology: String) -> Bool {
  let chars = string_to_charlist(topology)
  let full_chars = [102, 117, 108, 108] // "full"
  let line_chars = [108, 105, 110, 101] // "line"
  let chars_3d = [51, 68] // "3D"
  let chars_imp3d = [105, 109, 112, 51, 68] // "imp3D"
  
  case chars_equal(chars, full_chars) {
    True -> True
    False -> case chars_equal(chars, line_chars) {
      True -> True
      False -> case chars_equal(chars, chars_3d) {
        True -> True
        False -> chars_equal(chars, chars_imp3d)
      }
    }
  }
}

fn validate_algorithm(algorithm: String) -> Bool {
  let chars = string_to_charlist(algorithm)
  let gossip_chars = [103, 111, 115, 115, 105, 112] // "gossip"
  let push_sum_chars = [112, 117, 115, 104, 45, 115, 117, 109] // "push-sum"
  
  case chars_equal(chars, gossip_chars) {
    True -> True
    False -> chars_equal(chars, push_sum_chars)
  }
}

fn chars_equal(chars1: List(Int), chars2: List(Int)) -> Bool {
  case chars1, chars2 {
    [], [] -> True
    [c1, ..rest1], [c2, ..rest2] -> case c1 == c2 {
      True -> chars_equal(rest1, rest2)
      False -> False
    }
    _,_ -> False
  }
}

fn run_complete_simulation(num_nodes: Int, topology_str: String, algorithm: String) -> SimulationResult {
  debug_topology_simple(num_nodes, topology_str)
  let neighbors = topology.build_topology(num_nodes, topology_str)
  
  let chars = string_to_charlist(algorithm)
  let gossip_chars = [103, 111, 115, 115, 105, 112] // "gossip"
  let push_sum_chars = [112, 117, 115, 104, 45, 115, 117, 109] // "push-sum"
  
  case chars_equal(chars, gossip_chars) {
    True -> {
      print("Starting GOSSIP algorithm...\n")
      let actors = actor.spawn_gossip_actors(num_nodes, neighbors)
      actor.initiate_gossip(actors, "initial_rumor")
      let result = monitor_gossip_convergence(actors, topology_str, 0, num_nodes)
      actor.terminate_gossip_actors(actors)
      SimulationResult(
        converged: result.converged,
        total: num_nodes,
        rounds: result.rounds
      )
    }
    False -> case chars_equal(chars, push_sum_chars) {
      True -> {
        print("Starting PUSH-SUM algorithm...\n")
        let actors = actor.spawn_push_sum_actors(num_nodes, neighbors)
        actor.initiate_push_sum(actors)
        let result = monitor_push_sum_convergence(actors, topology_str, 0, num_nodes)
        actor.terminate_push_sum_actors(actors)
        SimulationResult(
          converged: result.converged,
          total: num_nodes,
          rounds: result.rounds
        )
      }
      False -> SimulationResult(0, num_nodes, 0)
    }
  }
}

pub type ConvergenceResult {
  ConvergenceResult(converged: Int, rounds: Int)
}

fn monitor_gossip_convergence(actors: List(process.Subject(actor.GossipMessage)), topology: String, round: Int, total: Int) -> ConvergenceResult {
  case round >= 50 {
    True -> ConvergenceResult(total, round)
    False -> {
      sleep(200)
      let converged = actor.monitor_gossip_convergence(actors)
      case round % 5 == 0 {
        True -> {
          print("Round ")
          print(int_to_string(round))
          print(": ")
          print(int_to_string(converged))
          print("/")
          print(int_to_string(total))
          print(" actors converged\n")
        }
        False -> Nil
      }
      case converged >= total {
        True -> ConvergenceResult(converged, round)
        False -> monitor_gossip_convergence(actors, topology, round + 1, total)
      }
    }
  }
}

fn monitor_push_sum_convergence(actors: List(process.Subject(actor.PushSumMessage)), topology: String, round: Int, total: Int) -> ConvergenceResult {
  case round >= 100 {
    True -> ConvergenceResult(total, round)
    False -> {
      sleep(300)
      let converged = actor.monitor_push_sum_convergence(actors)
      case round % 10 == 0 {
        True -> {
          print("Round ")
          print(int_to_string(round))
          print(": ")
          print(int_to_string(converged))
          print("/")
          print(int_to_string(total))
          print(" actors converged\n")
        }
        False -> Nil
      }
      case converged >= total {
        True -> ConvergenceResult(converged, round)
        False -> monitor_push_sum_convergence(actors, topology, round + 1, total)
      }
    }
  }
}

// FIXED: Corrected time unit from "microseconds" to "milliseconds"
fn print_results(result: SimulationResult, time_ms: Int) {
  let convergence_rate = case result.total {
    0 -> 0
    _ -> {result.converged * 100} / result.total
  }
  
  print("\n=== SIMULATION RESULTS ===\n")
  print("CONVERGED: ")
  print(int_to_string(result.converged))
  print("/")
  print(int_to_string(result.total))
  print(" actors (")
  print(int_to_string(convergence_rate))
  print("%)\n")
  print("ROUNDS: ")
  print(int_to_string(result.rounds))
  print("\nTIME: ")
  print(int_to_string(time_ms))
  print(" milliseconds\n")  // FIXED: Changed from "microseconds"
  print(int_to_string(time_ms))
}

// KEEPING YOUR EXISTING DEBUG FUNCTIONS
fn debug_topology_simple(num_nodes: Int, topology_str: String) {
  let neighbors = topology.build_topology(num_nodes, topology_str)
  print("=== TOPOLOGY DEBUG ===\n")
  debug_neighbors_list(neighbors, 0)
  print("======================\n")
}

fn debug_neighbors_list(topology: List(List(Int)), index: Int) {
  case topology {
    [] -> Nil
    [neighbors, ..rest] -> {
      print("Actor ")
      print(int_to_string(index))
      print(": ")
      print(int_to_string(list_length(neighbors)))
      print(" neighbors -> [")
      debug_print_neighbors(neighbors)
      print("]\n")
      debug_neighbors_list(rest, index + 1)
    }
  }
}

fn debug_print_neighbors(neighbors: List(Int)) {
  case neighbors {
    [] -> Nil
    [single] -> print(int_to_string(single))
    [first, ..rest] -> {
      print(int_to_string(first))
      print(",")
      debug_print_neighbors(rest)
    }
  }
}

fn list_length(list: List(a)) -> Int {
  case list {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}