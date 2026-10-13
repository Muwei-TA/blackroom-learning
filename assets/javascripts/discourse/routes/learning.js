import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class LearningRoute extends DiscourseRoute {
  queryParams = {
    username: { refreshModel: true },
    goal_id: { refreshModel: true },
  };
  async model(params) {
    const query = {};
    if (params.username) { query.username = params.username; }
    if (params.goal_id) { query.goal_id = params.goal_id; }
    const data = await ajax("/learning/data.json", { ignoreUnsent: false, data: query });
    return { ...data, query };
  }
}
