import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";

export default class LearningController extends Controller {
  queryParams = ["username", "goal_id"];
  @tracked username = "";
  @tracked goal_id = "";
}
