import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import { calendarDays, goalLink, profileLink } from "../lib/client-rules";

export default class LearningGoalCard extends Component {
  get statusText() { return i18n(`blackroom_learning.status.${this.args.goal.status}`); }
  get profileUrl() { return getURL(profileLink(this.args.goal.username)); }
  get goalUrl() { return getURL(goalLink(this.args.goal.id)); }
  get progressLabel() {
    return i18n("blackroom_learning.progress_label", { days: this.args.goal.progress.completed_days,
      target: this.args.goal.progress.target_days, percent: this.args.goal.progress.percent });
  }
  get dates() {
    const goal = this.args.goal;
    return calendarDays(goal.starts_on, goal.ends_on, goal.dates, this.args.today).map((cell) => ({
      ...cell, accessibleLabel: `${cell.date} ${i18n(`blackroom_learning.calendar.${cell.state}`)}`,
    }));
  }
  get showCheckin() { return this.args.goal.can_checkin && this.args.onCheckin; }
  get showCancel() { return this.args.goal.can_cancel && this.args.onCancel; }
  <template>
    <article class="bl-goal-card">
      <div class="bl-card-heading">
        <h3><a href={{this.goalUrl}}>{{@goal.name}}</a></h3>
        <span class="bl-state">{{this.statusText}}</span>
      </div>
      <a href={{this.profileUrl}} class="bl-member">{{@goal.username}}</a>
      <p class="bl-commitment">{{@goal.commitment}}</p>
      <p class="bl-date-range"><time datetime={{@goal.starts_on}}>{{@goal.starts_on}}</time> — <time datetime={{@goal.ends_on}}>{{@goal.ends_on}}</time></p>
      <progress max="100" value={{@goal.progress.percent}} aria-label={{this.progressLabel}}></progress>
      <p class="bl-progress-text">{{this.progressLabel}}</p>
      <p class="bl-hint">{{i18n "blackroom_learning.streak_label" current=@goal.streak.current longest=@goal.streak.longest}}</p>
      {{#if @goal.pending_checkins}}<p>{{i18n "blackroom_learning.pending_count" count=@goal.pending_checkins}}</p>{{/if}}
      <div class="bl-card-actions">
        {{#if this.showCheckin}}<button class="btn btn-primary" type="button" {{on "click" (fn @onCheckin @goal)}}>{{i18n "blackroom_learning.go_checkin"}}</button>{{/if}}
        {{#if @goal.flag_url}}<a href={{@goal.flag_url}}>{{i18n "blackroom_learning.original_flag"}}</a>{{/if}}
        {{#if this.showCancel}}<button class="btn btn-flat" type="button" {{on "click" (fn @onCancel @goal)}}>{{i18n "blackroom_learning.end_goal"}}</button>{{/if}}
      </div>
      {{#unless @compact}}
        <details class="bl-history"><summary>{{i18n "blackroom_learning.history"}}</summary>
          <ol class="bl-calendar" aria-label={{i18n "blackroom_learning.learning_calendar"}}>
            {{#each this.dates key="date" as |cell|}}
              <li data-state={{cell.state}}><time datetime={{cell.date}} title={{cell.accessibleLabel}} aria-label={{cell.accessibleLabel}}>{{cell.label}}</time></li>
            {{/each}}
          </ol>
          <p class="bl-hint">{{i18n "blackroom_learning.history_limit"}}</p>
          <ol class="bl-records">
            {{#each @goal.records as |record|}}<li><time datetime={{record.local_date}}>{{record.local_date}}</time> <a href={{record.url}}>{{record.title}}</a></li>{{/each}}
          </ol>
        </details>
      {{/unless}}
    </article>
  </template>
}
