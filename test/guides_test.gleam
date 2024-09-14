import guides/as_local_pubsub
import guides/as_part_of_supervisor
import guides/as_subject_index
import guides/readme

pub fn readme_test() {
  readme.main()
}

pub fn pubsub_test() {
  as_local_pubsub.main()
}

pub fn index_test() {
  as_subject_index.main()
}

pub fn supervisor_test() {
  as_part_of_supervisor.main()
}
