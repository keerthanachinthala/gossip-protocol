import gleam/otp/actor
import gleam/erlang/process
import gleam/list
import gleam/int
import gleam/float
import gleam/io
import gleam/option

// External functions we still need
@external(erlang, "rand", "uniform")
fn random_uniform(n: Int) -> Int

// Message types for gossip actors (SIMPLIFIED - no timers)
pub type GossipMessage {
  StartRumor(rumor: String)
  ReceiveRumor(rumor: String, sender_id: Int)
  SetGossipNeighbors(neighbors: List(process.Subject(GossipMessage)))
  GetGossipStatus(reply_to: process.Subject(GossipStatus))
  TerminateGossip
}

pub type GossipStatus {
  GossipStatus(actor_id: Int, rumor_count: Int, terminated: Bool)
}

// Message types for push-sum actors
pub type PushSumMessage {
  StartPushSum
  ReceiveValues(s: Float, w: Float, sender_id: Int)
  SetPushSumNeighbors(neighbors: List(process.Subject(PushSumMessage)))
  GetPushSumStatus(reply_to: process.Subject(PushSumStatus))
  TerminatePushSum
}

pub type PushSumStatus {
  PushSumStatus(actor_id: Int, current_ratio: Float, terminated: Bool)
}

// State for gossip actors
pub type GossipState {
  GossipState(
    id: Int,
    neighbors: List(process.Subject(GossipMessage)),
    rumors: List(String),
    rumor_count: Int,
    terminated: Bool
  )
}

// State for push-sum actors
pub type PushSumState {
  PushSumState(
    id: Int,
    neighbors: List(process.Subject(PushSumMessage)),
    s: Float,
    w: Float,
    ratio_history: List(Float),
    terminated: Bool,
    started: Bool
  )
}

// GOSSIP ACTOR - KEEPING YOUR EXISTING IMPLEMENTATION
pub fn start_gossip_actor(id: Int) -> Result(process.Subject(GossipMessage), actor.StartError) {
  let spec = actor.Spec(
    init: fn() {
      let state = GossipState(
        id: id,
        neighbors: [],
        rumors: [],
        rumor_count: 0,
        terminated: False
      )
      let selector = process.new_selector()
      actor.Ready(state, selector)
    },
    init_timeout: 1000,
    loop: handle_gossip_message
  )
  actor.start_spec(spec)
}

fn handle_gossip_message(
  message: GossipMessage,
  state: GossipState
) -> actor.Next(GossipMessage, GossipState) {
  case message {
    StartRumor(rumor) -> {
      io.println("Actor " <> int.to_string(state.id) <> " starting rumor: " <> rumor)
      let new_state = GossipState(
        ..state,
        rumors: [rumor, ..state.rumors],
        rumor_count: 1
      )
      // FIXED: Immediate aggressive spreading based on topology
      spread_rumor_multiple_times(new_state, rumor, 3)  // Spread 3 times initially
      actor.Continue(new_state, option.None)
    }
    ReceiveRumor(rumor, sender_id) -> {
      case state.terminated {
        True -> actor.Continue(state, option.None)
        False -> {
          let new_count = state.rumor_count + 1
          let new_terminated = new_count >= 10
          io.println("Actor " <> int.to_string(state.id) <> " received rumor from Actor " <> int.to_string(sender_id) <> " (count: " <> int.to_string(new_count) <> ")")
          let new_state = GossipState(
            ..state,
            rumors: [rumor, ..state.rumors],
            rumor_count: new_count,
            terminated: new_terminated
          )
          case new_terminated {
            True -> {
              io.println("*** Actor " <> int.to_string(state.id) <> " TERMINATING after " <> int.to_string(new_count) <> " rumors ***")
              actor.Continue(new_state, option.None)
            }
            False -> {
              // FIXED: Forward immediately based on neighbor count
              let forward_count = case list.length(state.neighbors) {
                n -> case n > 5 {
                  True -> 2   // Full topology: forward to 2 neighbors  
                  False -> 1  // Limited topology: forward to 1 neighbor
                }
              }
              spread_rumor_multiple_times(new_state, rumor, forward_count)
              actor.Continue(new_state, option.None)
            }
          }
        }
      }
    }
    SetGossipNeighbors(neighbors) -> {
      io.println("Actor " <> int.to_string(state.id) <> " received " <> int.to_string(list.length(neighbors)) <> " neighbors")
      actor.Continue(GossipState(..state, neighbors: neighbors), option.None)
    }
    GetGossipStatus(reply_to) -> {
      let status = GossipStatus(state.id, state.rumor_count, state.terminated)
      process.send(reply_to, status)
      actor.Continue(state, option.None)
    }
    TerminateGossip -> {
      actor.Stop(process.Normal)
    }
  }
}

// KEEPING YOUR EXISTING GOSSIP HELPER FUNCTIONS
fn spread_rumor_multiple_times(state: GossipState, rumor: String, times: Int) -> Nil {
  case times <= 0 || state.neighbors == [] {
    True -> Nil
    False -> {
      spread_rumor_once(state, rumor)
      spread_rumor_multiple_times(state, rumor, times - 1)
    }
  }
}

fn spread_rumor_once(state: GossipState, rumor: String) -> Nil {
  case state.neighbors {
    [] -> Nil
    neighbors -> {
      let neighbor_index = random_uniform(list.length(neighbors)) - 1
      case get_at_index(neighbors, neighbor_index) {
        Ok(neighbor) -> {
          process.send(neighbor, ReceiveRumor(rumor, state.id))
        }
        Error(_) -> Nil
      }
    }
  }
}

// PUSH-SUM ACTOR - WITH ADDED SEND LOGIC
pub fn start_push_sum_actor(id: Int) -> Result(process.Subject(PushSumMessage), actor.StartError) {
  let spec = actor.Spec(
    init: fn() {
      let state = PushSumState(
        id: id,
        neighbors: [],
        s: int.to_float(id),
        w: 1.0,
        ratio_history: [],
        terminated: False,
        started: False
      )
      let selector = process.new_selector()
      actor.Ready(state, selector)
    },
    init_timeout: 1000,
    loop: handle_push_sum_message
  )
  actor.start_spec(spec)
}

// ADDED: Helper function to send half values to neighbor
// FIXED: Properly update state to keep remaining half
fn send_half_values_to_neighbor(state: PushSumState) -> PushSumState {
  case state.neighbors {
    [] -> state
    neighbors -> {
      let neighbor_index = random_uniform(list.length(neighbors)) - 1
      case get_at_index(neighbors, neighbor_index) {
        Ok(neighbor) -> {
          let half_s = state.s /. 2.0
          let half_w = state.w /. 2.0
          
          io.println("Actor " <> int.to_string(state.id) <> " sending s=" <> float.to_string(half_s) <> ", w=" <> float.to_string(half_w))
          
          process.send(neighbor, ReceiveValues(half_s, half_w, state.id))
          
          // FIXED: Return state with remaining half (not sent half)
          PushSumState(
            ..state,
            s: half_s,  // Keep the other half
            w: half_w   // Keep the other half
          )
        }
        Error(_) -> state
      }
    }
  }
}

fn handle_push_sum_message(
  message: PushSumMessage,
  state: PushSumState
) -> actor.Next(PushSumMessage, PushSumState) {
  case message {
    StartPushSum -> {
      io.println("Actor " <> int.to_string(state.id) <> " starting push-sum")
      let new_state = PushSumState(..state, started: True)
      // ADDED: Send to neighbor when starting
      let final_state = send_half_values_to_neighbor(new_state)
      actor.Continue(final_state, option.None)
    }
    ReceiveValues(received_s, received_w, _sender_id) -> {
      let new_s = state.s +. received_s
      let new_w = state.w +. received_w
      let current_ratio = new_s /. new_w
      let new_history = [current_ratio, ..list.take(state.ratio_history, 2)]
      let converged = check_push_sum_convergence(new_history)
      
      let temp_state = PushSumState(
        ..state,
        s: new_s,
        w: new_w,
        ratio_history: new_history,
        terminated: converged
      )
      
      // ADDED: Send half values to neighbor if not terminated
      let final_state = case converged {
        True -> temp_state
        False -> send_half_values_to_neighbor(temp_state)
      }
      
      actor.Continue(final_state, option.None)
    }
    SetPushSumNeighbors(neighbors) -> {
      actor.Continue(PushSumState(..state, neighbors: neighbors), option.None)
    }
    GetPushSumStatus(reply_to) -> {
      let current_ratio = state.s /. state.w
      let status = PushSumStatus(state.id, current_ratio, state.terminated)
      process.send(reply_to, status)
      actor.Continue(state, option.None)
    }
    TerminatePushSum -> {
      actor.Stop(process.Normal)
    }
  }
}

fn check_push_sum_convergence(ratio_history: List(Float)) -> Bool {
  case ratio_history {
    [r1, r2, r3] -> {
      let diff1 = float.absolute_value(r1 -. r2)
      let diff2 = float.absolute_value(r2 -. r3)
      diff1 <. 0.0000000001 && diff2 <. 0.0000000001
    }
    _ -> False
  }
}

// KEEPING ALL YOUR EXISTING PUBLIC FUNCTIONS UNCHANGED
pub fn spawn_gossip_actors(num_nodes: Int, topology: List(List(Int))) -> List(process.Subject(GossipMessage)) {
  let actors = create_gossip_actors(0, num_nodes, [])
  io.println("Created " <> int.to_string(list.length(actors)) <> " gossip actors")
  setup_gossip_neighbors(actors, topology, 0)
  io.println("Finished setting up gossip neighbors")
  actors
}

pub fn spawn_push_sum_actors(num_nodes: Int, topology: List(List(Int))) -> List(process.Subject(PushSumMessage)) {
  let actors = create_push_sum_actors(0, num_nodes, [])
  setup_push_sum_neighbors(actors, topology, 0)
  actors
}

fn create_gossip_actors(current: Int, max: Int, acc: List(process.Subject(GossipMessage))) -> List(process.Subject(GossipMessage)) {
  case current >= max {
    True -> list.reverse(acc)
    False -> {
      case start_gossip_actor(current) {
        Ok(actor_subject) -> {
          create_gossip_actors(current + 1, max, [actor_subject, ..acc])
        }
        Error(_) -> {
          io.println("Failed to start gossip actor " <> int.to_string(current))
          create_gossip_actors(current + 1, max, acc)
        }
      }
    }
  }
}

fn create_push_sum_actors(current: Int, max: Int, acc: List(process.Subject(PushSumMessage))) -> List(process.Subject(PushSumMessage)) {
  case current >= max {
    True -> list.reverse(acc)
    False -> {
      case start_push_sum_actor(current) {
        Ok(actor_subject) -> {
          create_push_sum_actors(current + 1, max, [actor_subject, ..acc])
        }
        Error(_) -> {
          io.println("Failed to start push-sum actor " <> int.to_string(current))
          create_push_sum_actors(current + 1, max, acc)
        }
      }
    }
  }
}

fn setup_gossip_neighbors(actors: List(process.Subject(GossipMessage)), topology: List(List(Int)), index: Int) -> Nil {
  setup_gossip_neighbors_helper(actors, actors, topology, index)
}

fn setup_gossip_neighbors_helper(
  current_actors: List(process.Subject(GossipMessage)),
  all_actors: List(process.Subject(GossipMessage)),
  topology: List(List(Int)),
  index: Int
) -> Nil {
  case current_actors, topology {
    [], [] -> Nil
    [actor_subject, ..rest_actors], [neighbor_indices, ..rest_topology] -> {
      let neighbor_subjects = get_gossip_neighbor_subjects(neighbor_indices, all_actors)
      io.println("Setting up neighbors for actor " <> int.to_string(index) <> ": " <> int.to_string(list.length(neighbor_subjects)) <> " neighbors")
      process.send(actor_subject, SetGossipNeighbors(neighbor_subjects))
      setup_gossip_neighbors_helper(rest_actors, all_actors, rest_topology, index + 1)
    }
    _,_ -> {
      io.println("ERROR: Mismatch between actors and topology lengths")
      Nil
    }
  }
}

fn setup_push_sum_neighbors(actors: List(process.Subject(PushSumMessage)), topology: List(List(Int)), index: Int) -> Nil {
  setup_push_sum_neighbors_helper(actors, actors, topology, index)
}

fn setup_push_sum_neighbors_helper(
  current_actors: List(process.Subject(PushSumMessage)),
  all_actors: List(process.Subject(PushSumMessage)),
  topology: List(List(Int)),
  index: Int
) -> Nil {
  case current_actors, topology {
    [], [] -> Nil
    [actor_subject, ..rest_actors], [neighbor_indices, ..rest_topology] -> {
      let neighbor_subjects = get_push_sum_neighbor_subjects(neighbor_indices, all_actors)
      process.send(actor_subject, SetPushSumNeighbors(neighbor_subjects))
      setup_push_sum_neighbors_helper(rest_actors, all_actors, rest_topology, index + 1)
    }
    _,_ -> Nil
  }
}

fn get_gossip_neighbor_subjects(indices: List(Int), all_actors: List(process.Subject(GossipMessage))) -> List(process.Subject(GossipMessage)) {
  case indices {
    [] -> []
    [idx, ..rest] -> {
      case get_at_index(all_actors, idx) {
        Ok(actor_subject) -> [actor_subject, ..get_gossip_neighbor_subjects(rest, all_actors)]
        Error(_) -> {
          io.println("ERROR: Could not get actor at index " <> int.to_string(idx))
          get_gossip_neighbor_subjects(rest, all_actors)
        }
      }
    }
  }
}

fn get_push_sum_neighbor_subjects(indices: List(Int), all_actors: List(process.Subject(PushSumMessage))) -> List(process.Subject(PushSumMessage)) {
  list.filter_map(indices, fn(idx) { get_at_index(all_actors, idx) })
}

pub fn initiate_gossip(actors: List(process.Subject(GossipMessage)), rumor: String) -> Nil {
  case actors {
    [] -> Nil
    [first_actor, ..] -> {
      io.println("Initiating gossip with first actor")
      process.send(first_actor, StartRumor(rumor))
    }
  }
}

pub fn initiate_push_sum(actors: List(process.Subject(PushSumMessage))) -> Nil {
  case actors {
    [] -> Nil
    [first_actor, ..] -> {
      process.send(first_actor, StartPushSum)
    }
  }
}

pub fn terminate_gossip_actors(actors: List(process.Subject(GossipMessage))) -> Nil {
  list.each(actors, fn(actor_subject) {
    process.send(actor_subject, TerminateGossip)
  })
}

pub fn terminate_push_sum_actors(actors: List(process.Subject(PushSumMessage))) -> Nil {
  list.each(actors, fn(actor_subject) {
    process.send(actor_subject, TerminatePushSum)
  })
}

pub fn monitor_gossip_convergence(actors: List(process.Subject(GossipMessage))) -> Int {
  let status_subject = process.new_subject()
  list.each(actors, fn(actor_subject) {
    process.send(actor_subject, GetGossipStatus(status_subject))
  })
  collect_gossip_responses(status_subject, list.length(actors), 0, 0, 1000)
}

pub fn monitor_push_sum_convergence(actors: List(process.Subject(PushSumMessage))) -> Int {
  let status_subject = process.new_subject()
  list.each(actors, fn(actor_subject) {
    process.send(actor_subject, GetPushSumStatus(status_subject))
  })
  collect_push_sum_responses(status_subject, list.length(actors), 0, 0, 1000)
}

fn collect_gossip_responses(subject: process.Subject(GossipStatus), total: Int, collected: Int, terminated_count: Int, timeout: Int) -> Int {
  case collected >= total {
    True -> {
      terminated_count
    }
    False -> {
      case process.receive(subject, timeout) {
        Ok(status) -> {
          let new_terminated = case status.terminated {
            True -> terminated_count + 1
            False -> terminated_count
          }
          collect_gossip_responses(subject, total, collected + 1, new_terminated, timeout)
        }
        Error(_) -> {
          terminated_count
        }
      }
    }
  }
}

fn collect_push_sum_responses(subject: process.Subject(PushSumStatus), total: Int, collected: Int, terminated_count: Int, timeout: Int) -> Int {
  case collected >= total {
    True -> terminated_count
    False -> {
      case process.receive(subject, timeout) {
        Ok(status) -> {
          let new_terminated = case status.terminated {
            True -> terminated_count + 1
            False -> terminated_count
          }
          collect_push_sum_responses(subject, total, collected + 1, new_terminated, timeout)
        }
        Error(_) -> terminated_count
      }
    }
  }
}

fn get_at_index(list: List(a), index: Int) -> Result(a, Nil) {
  case index < 0 {
    True -> Error(Nil)
    False -> get_at_index_helper(list, index, 0)
  }
}

fn get_at_index_helper(list: List(a), target: Int, current: Int) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [first, ..rest] -> case current == target {
      True -> Ok(first)
      False -> get_at_index_helper(rest, target, current + 1)
    }
  }
}