import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import LearningGoalCard from "../../components/learning-goal-card";
import LearningGoalForm from "../../components/learning-goal-form";

export default class LearningFlagPanel extends Component {
  @service siteSettings;
  @tracked data = null;
  @tracked busy = false;
  @tracked error = "";
  constructor() {
    super(...arguments);
    if (this.isFlag) { this.refresh(); }
  }
  get topic() { return this.args.model || this.args.topic || this.args.outletArgs?.model || this.args.outletArgs?.topic; }
  get isFlag() { return this.siteSettings.blackroom_learning_enabled && this.topic?.id === this.siteSettings.blackroom_learning_flag_topic_id; }
  get homeUrl() { return getURL("/learning"); }
  get goals() { return this.data?.goals.slice(0, 4) || []; }
  get canCreate() {
    return this.data?.can_create && !this.data.my_goals.some((goal) => goal.ends_on >= this.data.today && ["active", "scheduled", "awaiting_approval", "unavailable"].includes(goal.status));
  }
  @action async refresh() {
    if (!this.isFlag || this.busy) { return; }
    this.busy = true;
    try {
      const data = await ajax("/learning/data.json", { ignoreUnsent: false });
      if (!this.isDestroying && !this.isDestroyed && this.isFlag) { this.data = data; this.error = ""; }
    } catch {
      if (!this.isDestroying && !this.isDestroyed) { this.error = i18n("blackroom_learning.request_failed"); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }
  <template>
    {{#if this.isFlag}}
      <aside class="bl-flag-panel">
        <h2>{{i18n "blackroom_learning.flag_panel_title"}}</h2>
        <p><a href={{this.homeUrl}}>{{i18n "blackroom_learning.all_goals"}}</a> · <button class="btn btn-flat" type="button" disabled={{this.busy}} {{on "click" this.refresh}}>{{i18n "blackroom_learning.refresh"}}</button></p>
        {{#if this.canCreate}}<details><summary>{{i18n "blackroom_learning.set_goal"}}</summary><LearningGoalForm @today={{this.data.today}} @onSaved={{this.refresh}} /></details>{{/if}}
        <div class="bl-goal-grid">{{#each this.goals key="id" as |goal|}}<LearningGoalCard @goal={{goal}} @today={{this.data.today}} @compact={{true}} />{{/each}}</div>
        {{#if this.error}}<p role="status">{{this.error}}</p>{{/if}}
      </aside>
    {{/if}}
  </template>
}
